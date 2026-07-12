;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sub-K - a very small web server ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;           m.power 2026          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;
;; environment setup ;;
;;;;;;;;;;;;;;;;;;;;;;;
.386                                 ; 32-bit x86 instruction set
.model flat, stdcall                 ; flat memory model, Win32 convention
option casemap:none                  ; preserve symbol case

;;;;;;;;;;;;;;;
;; constants ;;
;;;;;;;;;;;;;;;
INVALID_SOCKET        equ -1         ; socket() failure return value
SOCKET_ERROR          equ -1         ; winsock error return value
AF_INET               equ  2         ; ipv4 address family
SOCK_STREAM           equ  1         ; stream socket type
IPPROTO_TCP           equ  6         ; tcp protocol
INADDR_ANY            equ  0         ; bind to all local interfaces
PORT_8080             equ  901Fh     ; port 8080 in network byte order

GENERIC_READ          equ  80000000h ; read access for CreateFileA
OPEN_EXISTING         equ  3         ; require existing file for CreateFileA
FILE_ATTRIBUTE_NORMAL equ  80h       ; normal file with no special attributes
INVALID_HANDLE_VALUE  equ -1         ; CreateFileA failure return value

STD_OUTPUT_HANDLE     equ -11        ; console output handle for GetStdHandle