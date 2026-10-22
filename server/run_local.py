"""本地双栈启动：同时监听 IPv4 与 IPv6，绕过 uvicorn 单 host 单协议族的限制。

uvicorn 的 bind_socket 只建一个 socket（host 含 ":" 一律 AF_INET6 且
v6only=1），无法用一个 host 同时服务公网 IPv6 和内网 IPv4，因此这里
预建两个 socket 传给 Server.serve(sockets=...)。仅本地自托管使用。
"""

import socket

import uvicorn

PORT = 18000


def make_socket(family: socket.AddressFamily) -> socket.socket:
    sock = socket.socket(family=family, type=socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", PORT))
    sock.listen(2048)
    sock.set_inheritable(True)
    return sock


def main() -> None:
    config = uvicorn.Config(
        "agent_server.app:create_app",
        factory=True,
        workers=1,
    )
    server = uvicorn.Server(config)
    server.run(sockets=[make_socket(socket.AF_INET), make_socket(socket.AF_INET6)])


# spawn 出的 event worker 子进程会重新导入本模块，没有这个守卫会再次绑端口
if __name__ == "__main__":
    main()
