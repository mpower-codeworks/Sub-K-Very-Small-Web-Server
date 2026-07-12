;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sub-K - a very small web server ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;           m.power 2026          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; using http://localhost:8080/

;; first build w/ trial "hello" - 552 bytes exe (11.7MB RAM use)
;; modified to load index.htm   - 657 bytes exe

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

STD_OUTPUT_HANDLE     equ -11        ; console output handle for GetStdHandle

SOCKADDR_IN_SIZE      equ  16        ; byte size of sockaddr_in

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; add for loading an html file
FILE_SHARE_READ       equ  1          ; allow others to read file while open
FILEBUF_SIZE          equ  1024       ; file read chunk size

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; add for loading an html file
CreateFileA PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD ; open file
ReadFile    PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD                 ; read file bytes
CloseHandle PROTO :DWORD                                                 ; close file handle

;;;;;;;;;;
;; data ;;
;;;;;;;;;;
.data

wsaData     db 400 dup(0)            ; storage for WSAStartup results

serverAddr  dw AF_INET               ; sockaddr_in: IPv4 address family
            dw PORT_8080             ; sockaddr_in: port 8080, network order
            dd INADDR_ANY            ; sockaddr_in: bind to all local interfaces
            db 8 dup(0)              ; sockaddr_in: unused padding bytes

requestBuf  db 1024 dup(0)           ; request buffer / file chunk buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; replace old httpResp block
indexName   db "index.htm",0         ; default page to serve

okHeader    db "HTTP/1.0 200 OK",13,10
            db "Connection: close",13,10
            db "Content-Type: text/html",13,10
            db 13,10

okHeaderLen equ $ - okHeader         ; 200 response header length

notFound    db "HTTP/1.0 404 Not Found",13,10
            db "Connection: close",13,10
            db "Content-Type: text/plain",13,10
            db 13,10
            db "404",13,10

notFoundLen equ $ - notFound         ; 404 response length

bytesRead   dd 0                     ; bytes read from file

;;(no longer used)
;;httpResp    db "HTTP/1.0 200 OK",13,10
;;            db "Connection: close",13,10
;;            db "Content-Type: text/html",13,10
;;            db 13,10
;;            db "hello",13,10       ; trial message for first run

httpRespLen equ $ - httpResp         ; response length for send()

;;;;;;;;;;
;; code ;;
;;;;;;;;;;
.code

start:

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

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; replace old fixed http response block
    ;;; open index.htm
    push 0                           ; no template file
    push FILE_ATTRIBUTE_NORMAL       ; normal file attributes
    push OPEN_EXISTING               ; file must already exist
    push 0                           ; no security attributes
    push FILE_SHARE_READ             ; allow shared reading
    push GENERIC_READ                ; open for reading
    push offset indexName            ; file name
    call CreateFileA                 ; open index.htm
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

    ;;; close index.htm
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
    
    ;;; send fixed HTTP response (no longer used)
    ;;push 0                         ; no special send flags
    ;;push httpRespLen               ; response length
    ;;push offset httpResp           ; response bytes
    ;;push esi                       ; client socket
    ;;call send                      ; send HTTP response

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