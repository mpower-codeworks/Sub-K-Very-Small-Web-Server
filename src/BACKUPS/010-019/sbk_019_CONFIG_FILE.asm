;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sub-K - a very small web server ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;           m.power 2026          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; using http://localhost:8080/

;; first build w/ trial "hello" - 552 bytes exe (11.7MB RAM use)
;; modified to load index.htm   - 657 bytes exe
;; add read/process config file - 741 bytes exe

;;;;;;;;;;;;;;;;;;;;;;;
;; environment setup ;;
;;;;;;;;;;;;;;;;;;;;;;;
.386                                 ; 32-bit x86 instruction set
.model flat, stdcall                 ; flat memory model, Win32 calling convention
option casemap:none                  ; preserve symbol case exactly

;;;;;;;;;;;;;;;
;; constants ;;
;;;;;;;;;;;;;;;
INVALID_SOCKET        equ -1         ; socket() failure return value
SOCKET_ERROR          equ -1         ; Winsock error return value
AF_INET               equ  2         ; IPv4 address family
SOCK_STREAM           equ  1         ; stream socket type
IPPROTO_TCP           equ  6         ; TCP protocol
INADDR_ANY            equ  0         ; bind to all local interfaces
PORT_8080             equ  901Fh     ; port 8080 in network byte order

GENERIC_READ          equ  80000000h ; read access for CreateFileA
OPEN_EXISTING         equ  3         ; require existing file for CreateFileA
FILE_ATTRIBUTE_NORMAL equ  80h       ; normal file with no special attributes
INVALID_HANDLE_VALUE  equ -1         ; CreateFileA failure return value

SOCKADDR_IN_SIZE      equ  16        ; byte size of sockaddr_in
FILE_SHARE_READ       equ  1         ; allow others to read file while open
FILEBUF_SIZE          equ  1024      ; file read chunk size
CONFIGBUF_SIZE        equ  127       ; config bytes to read, leaving terminator

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; imports - change to proto for argument byte counts ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ExitProcess PROTO :DWORD                         ; terminate process with exit code
WSAStartup  PROTO :WORD,  :DWORD                 ; initialize Winsock before socket calls
socket      PROTO :DWORD, :DWORD, :DWORD         ; create a new network socket
bind        PROTO :DWORD, :DWORD, :DWORD         ; assign local address and port to socket
listen      PROTO :DWORD, :DWORD                 ; mark socket ready to accept connections
accept      PROTO :DWORD, :DWORD, :DWORD         ; accept an incoming client connection
recv        PROTO :DWORD, :DWORD, :DWORD, :DWORD ; receive data from connected socket
send        PROTO :DWORD, :DWORD, :DWORD, :DWORD ; send data to connected socket
closesocket PROTO :DWORD                         ; close a socket connection

CreateFileA PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD ; open file
ReadFile    PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD                 ; read file bytes
CloseHandle PROTO :DWORD                                                 ; close file handle

;;;;;;;;;;
;; data ;;
;;;;;;;;;;
.data

wsaData      db 400 dup(0)           ; storage for WSAStartup results

serverAddr   dw AF_INET              ; sockaddr_in: IPv4 address family
             dw PORT_8080            ; sockaddr_in: port 8080, network order
             dd INADDR_ANY           ; sockaddr_in: bind to all local interfaces
             db 8 dup(0)             ; sockaddr_in: unused padding bytes

requestBuf   db 1024 dup(0)          ; request buffer / file chunk buffer

indexName    db "index.htm",0        ; fallback start page to serve
configName   db "tws.config",0       ; configuration file name
configBuf    db 128 dup(0)           ; config line buffer
startPagePtr dd offset indexName     ; active start page filename pointer

okHeader     db "HTTP/1.0 200 OK",13,10
             db "Connection: close",13,10
             db "Content-Type: text/html",13,10
             db 13,10

okHeaderLen  equ $ - okHeader        ; 200 response header length

notFound     db "HTTP/1.0 404 Not Found",13,10
             db "Connection: close",13,10
             db "Content-Type: text/plain",13,10
             db 13,10
             db "404",13,10

notFoundLen  equ $ - notFound        ; 404 response length

bytesRead    dd 0                    ; bytes read from file

;;;;;;;;;;
;; code ;;
;;;;;;;;;;
.code

start:

    ;;; load start page from config
    push 0                           ; no template file
    push FILE_ATTRIBUTE_NORMAL       ; normal file attributes
    push OPEN_EXISTING               ; config must already exist
    push 0                           ; no security attributes
    push FILE_SHARE_READ             ; allow shared reading
    push GENERIC_READ                ; open for reading
    push offset configName           ; config file name
    call CreateFileA                 ; open tws.config
    cmp  eax, INVALID_HANDLE_VALUE   ; did config open fail?
    je   config_done                 ; keep default page if missing
    mov  edi, eax                    ; save config file handle


    ;;; read config file
    push 0                           ; no overlapped I/O
    push offset bytesRead            ; receives byte count
    push CONFIGBUF_SIZE              ; leave room for zero terminator
    push offset configBuf            ; config buffer
    push edi                         ; config file handle
    call ReadFile                    ; read config file


    ;;; close config file
    push edi                         ; config file handle
    call CloseHandle                 ; close config file


    ;;; validate start setting
    cmp  dword ptr [bytesRead], 6         ; enough bytes for "start "?
    jbe  config_done                      ; keep default if too short
    cmp  dword ptr [configBuf], 72617473h ; starts with "star"?
    jne  config_done                      ; keep default if not start setting
    cmp  word ptr [configBuf+4], 2074h    ; followed by "t "?
    jne  config_done                      ; keep default if not start setting
    mov  eax, offset configBuf            ; point to config buffer
    add  eax, 6                           ; skip "start "
    mov  dword ptr [startPagePtr], eax    ; use configured start page
    mov  edi, eax                         ; scan configured filename


config_trim:

    ;;; trim config file line ending
    mov  al, byte ptr [edi]          ; get current filename byte
    cmp  al, 13                      ; carriage return?
    je   config_zero                 ; terminate filename
    cmp  al, 10                      ; line feed?
    je   config_zero                 ; terminate filename
    cmp  al, 0                       ; end of buffer/string?
    je   config_done                 ; config is ready
    inc  edi                         ; advance filename scan
    jmp  config_trim                 ; keep scanning


config_zero:

    ;;; terminate configured filename
    mov  byte ptr [edi], 0           ; replace line ending with zero


config_done:

    ;;; initialize winsock
    push offset wsaData              ; pointer to WSADATA buffer
    push 0202h                       ; request Winsock version 2.2
    call WSAStartup                  ; start Winsock
    test eax, eax                    ; did WSAStartup succeed?
    jnz  exit_app                    ; exit if Winsock failed


    ;;; create listening socket
    push IPPROTO_TCP                 ; use TCP protocol
    push SOCK_STREAM                 ; create stream socket
    push AF_INET                     ; use IPv4
    call socket                      ; create server socket
    cmp  eax, INVALID_SOCKET         ; did socket creation fail?
    je   exit_app                    ; exit if socket failed
    mov  ebx, eax                    ; save server socket in EBX


    ;;; bind socket to port
    push SOCKADDR_IN_SIZE            ; size of sockaddr_in
    push offset serverAddr           ; local address and port
    push ebx                         ; server socket
    call bind                        ; bind socket to address
    cmp  eax, SOCKET_ERROR           ; did bind fail?
    je   close_server                ; close socket and exit if failed


    ;;; listen for connections
    push 1                           ; backlog: allow one waiting connection
    push ebx                         ; server socket
    call listen                      ; begin listening
    cmp  eax, SOCKET_ERROR           ; did listen fail?
    je   close_server                ; close socket and exit if failed


server_loop:

    ;;; accept browser connection
    push 0                           ; no client address length needed
    push 0                           ; no client address buffer needed
    push ebx                         ; server socket
    call accept                      ; accept incoming connection
    cmp  eax, INVALID_SOCKET         ; did accept fail?
    je   server_loop                 ; keep waiting if accept failed
    mov  esi, eax                    ; save client socket in ESI

    ;;; receive browser request
    push 0                           ; no special recv flags
    push 1024                        ; request buffer size
    push offset requestBuf           ; request buffer
    push esi                         ; client socket
    call recv                        ; receive HTTP request
    cmp  eax, 0                      ; did client send anything?
    jle  close_client                ; close if recv failed or disconnected

    ;;; open start page
    push 0                           ; no template file
    push FILE_ATTRIBUTE_NORMAL       ; normal file attributes
    push OPEN_EXISTING               ; file must already exist
    push 0                           ; no security attributes
    push FILE_SHARE_READ             ; allow shared reading
    push GENERIC_READ                ; open for reading
    push dword ptr [startPagePtr]    ; start page file name
    call CreateFileA                 ; open start page
    cmp  eax, INVALID_HANDLE_VALUE   ; did file open fail?
    je   send_404                    ; send 404 if missing
    mov  edi, eax                    ; save file handle in EDI


    ;;; send HTTP 200 header
    push 0                           ; no special send flags
    push okHeaderLen                 ; header length
    push offset okHeader             ; header bytes
    push esi                         ; client socket
    call send                        ; send HTTP header


file_loop:

    ;;; read file chunk
    push 0                           ; no overlapped I/O
    push offset bytesRead            ; receives byte count
    push FILEBUF_SIZE                ; bytes to read
    push offset requestBuf           ; file chunk buffer
    push edi                         ; file handle
    call ReadFile                    ; read file data
    test eax, eax                    ; did ReadFile fail?
    jz   close_file                  ; stop if read failed
    cmp  dword ptr [bytesRead], 0    ; end of file?
    je   close_file                  ; stop at EOF


    ;;; send file chunk
    push 0                           ; no special send flags
    push dword ptr [bytesRead]       ; bytes read from file
    push offset requestBuf           ; file chunk bytes
    push esi                         ; client socket
    call send                        ; send file chunk
    jmp  file_loop                   ; continue reading file


close_file:

    ;;; close start page
    push edi                         ; file handle
    call CloseHandle                 ; close file
    jmp  close_client                ; close browser connection


send_404:

    ;;; send missing file response
    push 0                           ; no special send flags
    push notFoundLen                 ; response length
    push offset notFound             ; response bytes
    push esi                         ; client socket
    call send                        ; send 404 response


close_client:

    ;;; close browser connection
    push esi                         ; client socket
    call closesocket                 ; close client connection
    jmp  server_loop                 ; wait for next browser request

close_server:

    ;;; close server socket
    push ebx                         ; server socket
    call closesocket                 ; close listening socket

exit_app:

    ;;; exit process
    push 0                           ; process exit code
    call ExitProcess                 ; terminate program

end start