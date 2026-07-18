;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sub-K - a very small web server ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;           m.power 2026          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; using http://localhost:8080/

;; first build w/ trial "hello"    - 552 bytes exe (11.7MB RAM use)
;; modified to load index.htm      - 657 bytes exe
;; add read/process config file    - 741 bytes exe
;; add cuncurrent session threads  - 834 bytes exe
;; -- tested with simultaneous 
;; -- connections from iPhone, 
;; -- Apple II, Win11, WinSvr2019
;; add path request (images/pages) - 908 bytes exe
;; removed config file for space   - 825 bytes exe
;; -- easy to add back in later
;; add MIME TYPE support           - 932 bytes exe
;; -- renamed to Sub-K
;; -- Tiny Web Server name
;; -- was already taken
;; remove unused functions         - 890 bytes exe
;; make EBP point directly
;;    at the thread buffer         - 872 bytes exe
;; remove both connection: close   - 861 bytes exe
;; 

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;One path escape is still possible
;By inspection, the sanitizer rejects .. and colons, but it
;accepts an additional leading slash or a literal backslash
;A request resembling: 
;GET //Windows/win.ini HTTP/1.0
;can become:
;\Windows\win.ini
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
PORT_8080             equ  5000h;901Fh     ; port 8080 in network byte order

GENERIC_READ          equ  80000000h ; read access for CreateFileA
OPEN_EXISTING         equ  3         ; require existing file for CreateFileA
FILE_ATTRIBUTE_NORMAL equ  80h       ; normal file with no special attributes
INVALID_HANDLE_VALUE  equ -1         ; CreateFileA failure return value

SOCKADDR_IN_SIZE      equ  16        ; byte size of sockaddr_in
FILE_SHARE_READ       equ  1         ; allow others to read file while open
FILEBUF_SIZE          equ  1024      ; file read chunk size
;CONFIGBUF_SIZE        equ  127       ; config bytes to read, leaving terminator

THREAD_BYTES_READ     equ -4         ; worker local bytes-read storage
THREAD_FILE_BUF       equ  0         ; EBP points directly to worker file buffer
LISTEN_BACKLOG        equ  10        ; queued client connection limit

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

CreateThread PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD        ; concurrent worker thread

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
;configName   db "tws.config",0       ; configuration file name
;configBuf    db 128 dup(0)           ; config line buffer
;startPagePtr dd offset indexName     ; active start page filename pointer

okHeader     db "HTTP/1.0 200 OK",13,10
             ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	     ;;db "Connection: close",13,10 ;;
	     ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
             db "Content-Type: "

okHeaderLen  equ $ - okHeader        ; 200 response header prefix length

MIMELEN      equ 16                  ; padded MIME line plus blank line
mimeHtml     db "text/html   ",13,10,13,10 ; .htm/.html/default
mimeCss      db "text/css    ",13,10,13,10 ; .css
mimePng      db "image/png   ",13,10,13,10 ; .png
mimeJpg      db "image/jpeg  ",13,10,13,10 ; .jpg
mimeGif      db "image/gif   ",13,10,13,10 ; .gif
mimeBmp      db "image/bmp   ",13,10,13,10 ; .bmp
mimeIco      db "image/x-icon",13,10,13,10 ; .ico

notFound     db "HTTP/1.0 404 Not Found",13,10
             ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	     ;;db "Connection: close",13,10 ;;
	     ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; load start page from config ------------       ;;
    ;; config file support temporarily disabled       ;;
    ;; default start page is compiled in as index.htm ;;
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;    push 0                           ; no template file
;    push FILE_ATTRIBUTE_NORMAL       ; normal file attributes
;    push OPEN_EXISTING               ; config must already exist
;    push 0                           ; no security attributes
;    push FILE_SHARE_READ             ; allow shared reading
;    push GENERIC_READ                ; open for reading
;    push offset configName           ; config file name
;    call CreateFileA                 ; open tws.config
;    cmp  eax, INVALID_HANDLE_VALUE   ; did config open fail?
;    je   config_done                 ; keep default page if missing
;    mov  edi, eax                    ; save config file handle


    ;;; read config file
;    push 0                           ; no overlapped I/O
;    push offset bytesRead            ; receives byte count
;    push CONFIGBUF_SIZE              ; leave room for zero terminator
;    push offset configBuf            ; config buffer
;    push edi                         ; config file handle
;    call ReadFile                    ; read config file


    ;;; close config file
;    push edi                         ; config file handle
;    call CloseHandle                 ; close config file


    ;;; validate start setting
;    cmp  dword ptr [bytesRead], 6         ; enough bytes for "start "?
;    jbe  config_done                      ; keep default if too short
;    cmp  dword ptr [configBuf], 72617473h ; starts with "star"?
;    jne  config_done                      ; keep default if not start setting
;    cmp  word ptr [configBuf+4], 2074h    ; followed by "t "?
;    jne  config_done                      ; keep default if not start setting
;    mov  eax, offset configBuf            ; point to config buffer
;    add  eax, 6                           ; skip "start "
;    mov  dword ptr [startPagePtr], eax    ; use configured start page
;    mov  edi, eax                         ; scan configured filename


;config_trim:

    ;;; trim config file line ending
;    mov  al, byte ptr [edi]          ; get current filename byte
;    cmp  al, 13                      ; carriage return?
;    je   config_zero                 ; terminate filename
;    cmp  al, 10                      ; line feed?
;    je   config_zero                 ; terminate filename
;    cmp  al, 0                       ; end of buffer/string?
;    je   config_done                 ; config is ready
;    inc  edi                         ; advance filename scan
;    jmp  config_trim                 ; keep scanning


;config_zero:

    ;;; terminate configured filename
;    mov  byte ptr [edi], 0           ; replace line ending with zero

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
    push LISTEN_BACKLOG              ; queued client connection limit
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

    ;;; start client worker thread
    push 0                           ; no thread id needed
    push 0                           ; run immediately
    push esi                         ; client socket parameter
    push offset client_thread        ; worker thread entry point
    push 0                           ; default stack size
    push 0                           ; default security attributes
    call CreateThread                ; start worker thread
    test eax, eax                    ; did thread creation fail?
    jz   close_accepted              ; close client if thread failed

    ;;; release thread handle
    push eax                         ; thread handle
    call CloseHandle                 ; close our handle to worker thread
    jmp  server_loop                 ; accept another client


close_accepted:

    ;;; close client if worker failed
    push esi                         ; accepted client socket
    call closesocket                 ; close failed client connection
    jmp  server_loop                 ; keep serving

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; remove these lefovers ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;
;file_loop:

    ;;; read file chunk
    ;push 0                           ; no overlapped I/O
    ;push offset bytesRead            ; receives byte count
    ;push FILEBUF_SIZE                ; bytes to read
    ;push offset requestBuf           ; file chunk buffer
    ;push edi                         ; file handle
    ;call ReadFile                    ; read file data
    ;test eax, eax                    ; did ReadFile fail?
    ;jz   close_file                  ; stop if read failed
    ;cmp  dword ptr [bytesRead], 0    ; end of file?
    ;je   close_file                  ; stop at EOF


    ;;; send file chunk
    ;push 0                           ; no special send flags
    ;push dword ptr [bytesRead]       ; bytes read from file
    ;push offset requestBuf           ; file chunk bytes
    ;push esi                         ; client socket
    ;call send                        ; send file chunk
    ;jmp  file_loop                   ; continue reading file


;close_file:

    ;;; close start page
    ;push edi                         ; file handle
    ;call CloseHandle                 ; close file
    ;jmp  close_client                ; close browser connection


;send_404:

    ;;; send missing file response
    ;push 0                           ; no special send flags
    ;push notFoundLen                 ; response length
    ;push offset notFound             ; response bytes
    ;push esi                         ; client socket
    ;call send                        ; send 404 response


;close_client:

    ;;; close browser connection
    ;push esi                         ; client socket
    ;call closesocket                 ; close client connection
    ;jmp  server_loop                 ; wait for next browser request

close_server:

    ;;; close server socket
    push ebx                         ; server socket
    call closesocket                 ; close listening socket

exit_app:

    ;;; exit process
    push 0                           ; process exit code
    call ExitProcess                 ; terminate program
    
client_thread:

    ;;; create worker stack frame
    push ebp                         ; save caller frame
    push ebx                         ; save MIME pointer register
    push esi                         ; save nonvolatile register
    push edi                         ; save nonvolatile register
    mov  esi, dword ptr [esp+20]     ; get client socket parameter
    sub  esp, FILEBUF_SIZE + 4       ; reserve bytesRead + file buffer
    lea  ebp, [esp+4]                ; point EBP directly at file buffer


    ;;; receive browser request
    ;push 0                           ; no special recv flags
    ;push FILEBUF_SIZE                ; request buffer size
    ;lea  eax, [ebp+THREAD_FILE_BUF]  ; thread-local request buffer
    ;push eax                         ; request buffer
    ;push esi                         ; client socket
    ;call recv                        ; receive HTTP request
    ;cmp  eax, 0                      ; did client send anything?
    ;jle  thread_close_client         ; close if recv failed or disconnected
    
    ;;; receive browser request
    push 0                           ; no special recv flags
    push FILEBUF_SIZE - 1            ; leave room for zero terminator
    push ebp                         ; thread-local request buffer
    push esi                         ; client socket
    call recv                        ; receive HTTP request
    cmp  eax, 0                      ; did client send anything?
    jle  thread_close_client         ; close if recv failed or disconnected
    mov  byte ptr [ebp+eax], 0       ; terminate received request
    
    ;;; parse requested path
    cmp  dword ptr [ebp], 20544547h                 ; request starts with "GET "?
    jne  thread_send_404                            ; reject non-GET request
    cmp  byte ptr [ebp+4], '/'                      ; path starts with slash?
    jne  thread_send_404                            ; reject malformed path

    lea  edx, [ebp+5]                               ; point after "GET /"
    cmp  byte ptr [edx], ' '                        ; plain "/" request?
    je   thread_use_start_page                      ; serve configured start page


thread_path_scan:

    ;;; sanitize requested path
    mov  al, byte ptr [edx]          ; get path byte
    cmp  al, 0                       ; end of request buffer?
    je   thread_path_ready           ; terminate path here
    cmp  al, ' '                     ; end of HTTP path?
    je   thread_path_ready           ; terminate path here
    cmp  al, '?'                     ; query string begins?
    je   thread_path_ready           ; ignore query string
    cmp  al, 13                      ; carriage return?
    je   thread_path_ready           ; terminate path here
    cmp  al, 10                      ; line feed?
    je   thread_path_ready           ; terminate path here
    cmp  al, ':'                     ; drive/path colon?
    je   thread_send_404             ; reject absolute drive path
    cmp  al, '.'                     ; possible traversal?
    jne  thread_check_slash          ; not a dot
    cmp  byte ptr [edx+1], '.'       ; double dot?
    je   thread_send_404             ; reject parent traversal


thread_check_slash:

    ;;; convert URL slash to Windows slash
    cmp  al, '/'                     ; URL path separator?
    jne  thread_next_path_byte       ; keep byte as-is
    mov  byte ptr [edx], 5Ch         ; convert "/" to "\"


thread_next_path_byte:

    ;;; advance path scan
    inc  edx                         ; next path byte
    jmp  thread_path_scan            ; continue scanning


thread_path_ready:

    ;;; terminate requested filename
    mov  byte ptr [edx], 0            ; zero-terminate path


    ;;; choose MIME type from extension
    mov  ebx, offset mimeHtml         ; default to HTML for tiny server
    cmp  dword ptr [edx-4], 7373632Eh ; .css?
    jne  thread_check_png             ; try next extension
    mov  ebx, offset mimeCss          ; CSS MIME type
    jmp  thread_mime_ready            ; MIME type selected


thread_check_png:

    ;;; check PNG extension
    cmp  dword ptr [edx-4], 676E702Eh ; .png?
    jne  thread_check_jpg             ; try next extension
    mov  ebx, offset mimePng          ; PNG MIME type
    jmp  thread_mime_ready            ; MIME type selected


thread_check_jpg:

    ;;; check JPG extension
    cmp  dword ptr [edx-4], 67706A2Eh ; .jpg?
    jne  thread_check_gif             ; try next extension
    mov  ebx, offset mimeJpg          ; JPG MIME type
    jmp  thread_mime_ready            ; MIME type selected


thread_check_gif:

    ;;; check GIF extension
    cmp  dword ptr [edx-4], 6669672Eh ; .gif?
    jne  thread_check_bmp             ; try next extension
    mov  ebx, offset mimeGif          ; GIF MIME type
    jmp  thread_mime_ready            ; MIME type selected


thread_check_bmp:

    ;;; check BMP extension
    cmp  dword ptr [edx-4], 706D622Eh ; .bmp?
    jne  thread_check_ico             ; try next extension
    mov  ebx, offset mimeBmp          ; BMP MIME type
    jmp  thread_mime_ready            ; MIME type selected


thread_check_ico:

    ;;; check ICO extension
    cmp  dword ptr [edx-4], 6F63692Eh ; .ico?
    jne  thread_mime_ready            ; use default MIME type
    mov  ebx, offset mimeIco          ; ICO MIME type


thread_mime_ready:

    ;;; reopen request path pointer
    lea  edx, [ebp+5]                ; filename starts after "GET /"
    jmp  thread_open_file             ; open requested file


thread_use_start_page:

    ;;; use default start page
    mov  ebx, offset mimeHtml         ; default page is HTML
    mov  edx, offset indexName        ; default start page filename

    ;;; open start page
    ;push 0                           ; no template file
    ;push FILE_ATTRIBUTE_NORMAL       ; normal file attributes
    ;push OPEN_EXISTING               ; file must already exist
    ;push 0                           ; no security attributes
    ;push FILE_SHARE_READ             ; allow shared reading
    ;push GENERIC_READ                ; open for reading
    ;push offset indexName             ; default start page file name
    ;call CreateFileA                 ; open start page
    ;cmp  eax, INVALID_HANDLE_VALUE   ; did file open fail?
    ;je   thread_send_404             ; send 404 if missing
    ;mov  edi, eax                    ; save file handle in EDI

thread_open_file:

    ;;; open requested file
    push 0                           ; no template file
    push FILE_ATTRIBUTE_NORMAL       ; normal file attributes
    push OPEN_EXISTING               ; file must already exist
    push 0                           ; no security attributes
    push FILE_SHARE_READ             ; allow shared reading
    push GENERIC_READ                ; open for reading
    push edx                         ; requested filename
    call CreateFileA                 ; open requested file
    cmp  eax, INVALID_HANDLE_VALUE   ; did file open fail?
    je   thread_send_404             ; send 404 if missing
    mov  edi, eax                    ; save file handle in EDI

    ;;; send HTTP 200 header prefix
    push 0                           ; no special send flags
    push okHeaderLen                 ; header prefix length
    push offset okHeader             ; header prefix bytes
    push esi                         ; client socket
    call send                        ; send HTTP header prefix


    ;;; send selected MIME type
    push 0                           ; no special send flags
    push MIMELEN                     ; padded MIME line length
    push ebx                         ; selected MIME bytes
    push esi                         ; client socket
    call send                        ; send MIME type and blank line


thread_file_loop:

    ;;; read file chunk
    push 0                           ; no overlapped I/O
    lea  eax, [ebp+THREAD_BYTES_READ]; thread-local byte count
    push eax                         ; receives byte count
    push FILEBUF_SIZE                ; bytes to read
    push ebp                         ; thread-local file buffer
    push edi                         ; file handle
    call ReadFile                    ; read file data
    test eax, eax                    ; did ReadFile fail?
    jz   thread_close_file           ; stop if read failed
    cmp  dword ptr [ebp+THREAD_BYTES_READ], 0 ; end of file?
    je   thread_close_file           ; stop at EOF


    ;;; send file chunk
    push 0                           ; no special send flags
    push dword ptr [ebp+THREAD_BYTES_READ] ; bytes read from file
    push ebp                         ; thread-local file buffer
    push esi                         ; client socket
    call send                        ; send file chunk
    jmp  thread_file_loop            ; continue reading file


thread_close_file:

    ;;; close start page
    push edi                         ; file handle
    call CloseHandle                 ; close file


thread_close_client:

    ;;; close browser connection
    push esi                         ; client socket
    call closesocket                 ; close client connection
    jmp  thread_done                 ; finish worker thread


thread_send_404:

    ;;; send missing file response
    push 0                           ; no special send flags
    push notFoundLen                 ; response length
    push offset notFound             ; response bytes
    push esi                         ; client socket
    call send                        ; send 404 response
    jmp  thread_close_client         ; close browser connection


thread_done:

    ;;; destroy worker stack frame
    add  esp, FILEBUF_SIZE + 4       ; release local storage
    pop  edi                         ; restore nonvolatile register
    pop  esi                         ; restore nonvolatile register
    pop  ebx                         ; restore MIME pointer register
    pop  ebp                         ; restore caller frame
    xor  eax, eax                    ; thread return code
    ret  4                           ; return and remove thread parameter

end start
