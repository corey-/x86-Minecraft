format PE console 4.0 DLL
entry DllEntryPoint

include 'win32a.inc'

;defines
IPPROTO_TCP equ dword 6
SOCKET_ERROR equ dword -1
INVALID_SOCKET equ dword -1
INADDR_ANY equ 0
INFINITE equ 0xFFFFFFFF
HFILE_ERROR equ dword -1
MAX_PLAYERS equ 20

;structs
stplayer:
struc Player
{
  .x dw 128 * 32
  .y dw 128 * 32
  .z dw 2 * 32
  .yaw db 0
  .pitch db 0

  .name rb 64
  .namez rb 64

  .socket dd 0
  .socketLock rb 24

  .loadingWorld db 1
  .blockPacketQueue rb 8 * 50

  .banned db 0
  .hasExtendedBlocks db 0
}
sizePlayer equ $ - stplayer

struc Banlist
{
  .size dd 0
  .first dd 0
}

stbannode:
struc BanlistNode
{
  .name rb 64  ;player's name
  .next dd 0
}
sizeBanNode equ $ - stbannode

section '.text' code readable executable

proc DllEntryPoint hinstDLL,fdwReason,lpvReserved
	mov	eax,TRUE
	ret
endp

include 'Heartbeat.asm'
include 'PacketWriter.asm'
include 'Player.asm'
include 'BanlistWatch.asm'

;bool InitializeServer(int port)
;starts up winsock and creates a listening socket
;returns 0 if successful, -1 if not
proc InitializeServer port
	mov eax, [port]
	mov [sPort], eax
	;start up winsock
	invoke WSAStartup, 0x0002, wsaData
	or eax, eax
	jz .wsasuccessful
	mov eax, -1
	ret
  .wsasuccessful:
	;check version
	cmp byte [wsaData.wVersion], 2
	jge .versionOK
	mov eax, -1
	ret
  .versionOK:
	;create socket
	invoke socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
	cmp eax, INVALID_SOCKET
	jne .socketCreated
	mov eax, -1
	ret
  .socketCreated:
	mov [serverSocket], eax
	;bind socket
	invoke htons, [port]
	mov [sSockAddr.sin_family], AF_INET
	mov [sSockAddr.sin_port], ax
	mov [sSockAddr.sin_addr], INADDR_ANY
	invoke bind, [serverSocket], sSockAddr, 16 ;sizeof sSockAddr
	or eax, eax
	jz .socketBound
	mov eax, -1
	ret
  .socketBound:
	;put socket in listening mode
	invoke listen, [serverSocket], MAX_PLAYERS
	or eax, eax
	jz .listening
	mov eax, -1
	ret
  .listening:
	mov [serverClosing], 0
	mov [playersCount], 0

	mov eax, 0
	mov ecx, MAX_PLAYERS
	mov edi, players
	rep stosb

	invoke htonl, 4194304
	mov [worldSize], eax
	stdcall generateSalt
	cinvoke _beginthread, LoopHeartbeat, 0
	cinvoke _beginthread, WatchBanlist, 0
	invoke InitializeCriticalSection, worldDataLock
	invoke InitializeCriticalSection, banlistLock
	stdcall initializeWorld
	ret
endp

proc ListenerLoop
   .loop:
	invoke accept, [serverSocket], 0, 0
	cmp eax, INVALID_SOCKET
	je .checkClosing

	mov [clientSocket], eax
	cmp [playersCount], MAX_PLAYERS
	je .serverFull

	cinvoke printf, playerConnecting

	;assign socket to next empty slot
	mov ecx, 0
  .findSlot:
	cmp [players+ecx*4], 0
	je @f
	inc ecx
	jmp .findSlot
     @@:
	cinvoke _beginthread, PlayerLoop, 0, ecx
	cmp eax, -1
	je @f
	invoke Sleep, 1000
	jmp .checkClosing
     @@:
	cinvoke printf, playerLoginFailed
	jmp .checkClosing

  .serverFull:
	stdcall SendDisconnectPacket, [clientSocket], serverFull
	invoke closesocket, [clientSocket]
	cinvoke printf, playerLoginFailed

  .checkClosing:
	cmp [serverClosing], 1
	jne .loop
	ret
endp

;void ShutdownServer
proc ShutdownServer
     mov [serverClosing], 1
     invoke WSACleanup
     invoke DeleteCriticalSection, worldDataLock
     invoke DeleteCriticalSection, banlistLock
     stdcall saveWorld
     cmp eax, 0
     je @f
     cinvoke printf, worldSaveError
  @@:
     ret
endp



;#############################################
;bool initializeWorld
proc initializeWorld
     sub esp, 136
     invoke OpenFile, worldDataFile, esp, OF_READ
     cmp eax, HFILE_ERROR
     jne @f
     mov eax, -1
     add esp, 136
     ret
  @@:
     push eax
     sub esp, 4
     invoke ReadFile, eax, worldData, 4194304, esp, 0
     add esp, 4
     cmp eax, 0
     jg @f
     mov eax, -1
     add esp, 136
     ret
  @@:
     pop eax
     invoke CloseHandle, eax
     mov eax, 0
     add esp, 136
     ret
endp

proc saveWorld
     sub esp, 136
     invoke OpenFile, worldDataFile, esp, OF_READWRITE
     cmp eax, HFILE_ERROR
     jne @f
     mov eax, -1
     add esp, 136
     ret
  @@:
     push eax
     sub esp, 4
     invoke WriteFile, eax, worldData, 4194304, esp, 0
     add esp, 4
     cmp eax, 0
     jg @f
     mov eax, -1
     add esp, 136
     ret
  @@:
     pop eax
     invoke CloseHandle, eax
     mov eax, 0
     add esp, 136
     ret
endp

;void broadcastMessage(Player* player, char* message)
proc broadcastMessage player, message
     local buffer1 rb 66
     local buffer2 rb 66
     push esi
     push edi
     push ebx
     lea ebx, [buffer1]
     lea edx, [buffer2]
     mov byte [ebx], 0x0d
     mov byte [edx], 0x0d
     mov byte [ebx+1], 255
     mov byte [edx+1], 255

     mov ecx, [player]
     virtual at ecx
	.p Player
     end virtual

     cld			;copy name to buffer1
     lea esi, [.p.name]
     lea edi, [ebx+2]
     mov ecx, 64
     rep movsb

     mov esi, [message] 	;copy message to buffer2
     lea edi, [edx+2]
     mov ecx, 64
     rep movsb

     virtual at edi
	 .player Player
     end virtual
     mov ecx, 0
  .sendloop:
     mov edi, [players+ecx*4]
     push ecx
     cmp edi, 0
     je @f
     cmp byte [.player.loadingWorld], 1
     je @f
     lea esi, [.player.socketLock]
     push edx
     push edx
     invoke EnterCriticalSection, esi
     invoke send, [.player.socket], ebx, 66, 0
     pop edx
     invoke send, [.player.socket], edx, 66, 0
     invoke LeaveCriticalSection, esi
     pop edx
  @@:
     pop ecx
     inc ecx
     cmp ecx, MAX_PLAYERS
     jl .sendloop

     pop ebx
     pop edi
     pop esi
     ret
endp

;void broadcastBlockPacket(char* blockpacket)
proc broadcastBlockPacket packet
    push edi
    push esi
    virtual at edi
       .player Player
    end virtual

    mov ecx, 0
 .sendloop:
    mov edi, [players+ecx*4]
    push ecx
    cmp edi, 0
    je .endloop
    cmp byte[.player.loadingWorld], 0
    je @f
    lea ebx, [.player.blockPacketQueue]
    mov ecx, 0
 .addqueue:
    cmp byte [ebx+ecx*8], 0
    jne .next
    mov esi, [packet]
    lea edi, [ebx+ecx*8]
    movsd
    movsd
 .next:
    inc ecx
    cmp ecx, 50
    jl .addqueue
    jmp .endloop
  @@:
    lea esi, [.player.socketLock]
    invoke EnterCriticalSection, esi
    invoke send, [.player.socket], [packet], 8, 0
    invoke LeaveCriticalSection, esi
 .endloop:
    pop ecx
    inc ecx
    cmp ecx, MAX_PLAYERS
    jl .sendloop

    pop esi
    pop edi
    ret
endp

proc broadcastMovement p, index
    mov ecx, 0
 .sendLoop:
    mov eax, [players+ecx*4]
    cmp eax, [p]
    je @f
    cmp eax, 0
    je @f
    push ecx
    stdcall SendTeleportPacket, [index], [p], eax
    pop ecx
 @@:
    inc ecx
    cmp ecx, MAX_PLAYERS
    jl .sendLoop
    ret
endp

proc generateSalt
    push ebx
    invoke GetTickCount
    mov ebx, 15
 @@:
    mov edx, 0
    mov ecx, 26
    div ecx
    add edx, 65
    mov [salt+ebx], dl
    imul eax, 104659
    dec ebx
    cmp ebx, 0
    jge @b
    pop ebx
    ret
endp

;bool verifyUsername(char* playerName, char* mppass)
proc verifyUsername playerName, mppass
    local buffer rb 100
    push esi
    push edi
    push ebx

    mov esi, salt     ;concatenate server salt and playername
    lea edi, [buffer] ;in buffer
    mov ecx, 16
    rep movsb
    mov esi, [playerName]
 @@:
    cmp byte[esi], 0
    je @f
    movsb
    jmp @b
  @@:
    mov byte[edi], 0

    lea edi, [buffer]
    cinvoke GenerateMD5, edi   ;get md5 sum salt + username, store in buffer
    mov ecx, 32 	       ;check if it equals mppass
    mov esi, [mppass]
    repe cmpsb
    jne .no

    pop ebx
    pop edi
    pop esi
    mov eax, 0
    ret

 .no:
    pop ebx
    pop edi
    pop esi
    mov eax, -1
    ret
endp

section '.data' data readable writeable
	playerConnecting db 'Player is connecting...', 10, 0
	playerLoginFailed db 'Player login failed.', 10, 0
	playerConnected db '%s connected.', 10, 0
	playerDisconnected db '%s disconnected.', 10, 0
	playerInvalidPass db 'You have been kicked. Invalid verification key.', 64-($-playerInvalidPass) dup 32
	playerBanned db 'You are banned from this server.', 64-($-playerBanned) dup 32

	worldDataFile db 'worldData.txt',0
	worldSaveError db 'The world was not saved properly. Replace worldData.txt with backup.', 10,0
	serverFull db 'Sorry, the server is full.',10, 0

	serverName db 'x86 Minecraft',	64-($-serverName) dup 32
	serverMOTD db 'Under Construction +hax',  64-($-serverMOTD) dup 32

	d db '%d',10,0

	;************for heartbeat*****************
	addrResult rd 1
	heartbeatSocket rd 1
	hostName db 'www.minecraft.net',0
	port80 db '80',0
	pathTemplate db 'GET /heartbeat.jsp?public=%s&max=%d&users=%d&port=%d&version=7&salt=%s&name=%s HTTP/1.1',13,10,'HOST: minecraft.net',13,10,13,10,0

	mcnetName db 'x86%20Minecraft',0
	publicServer db 'True',0;,0
	salt rb 16
	     db 0
	heartbeatInitialized db 'Heartbeat loop initialized', 10,0
	heartbeatSend db 'Send heartbeat.',10,0
	heartbeatError db 'Error code %d in heartbeat loop. Heartbeat loop has closed.',10,0
	;*******************************************

	;************for banlist watch**************
	banlistModified db 'Banlist was modified. Loading changes...',10,0
	banlistLoaded db 'Loaded %d bans',10,0
	banWatchError db 'Error in ban watch loop. Bans will not be updated until server restart.',10,0
	banFolder db '\BanList',0
	banFile db '\banlist.txt',0
	fileread db 'r',0
	fileChangeHandle rd 1
	changeFlag dd 0

	banlistLock rb 24
	banlist Banlist
	;*******************************************

	;************extensions*********************
	customBlocks db 'CustomBlocks', 64-($-customBlocks) dup 32
	;*******************************************

	wsaData WSADATA ?
	serverSocket rd 1
	clientSocket rd 1
	sSockAddr sockaddr_in ?
	sPort rd 1

	playersCount rd 1
	players rd MAX_PLAYERS

	worldSize rd 1
	worldData rb 4194304
	worldDataLock rb 24

	serverClosing rb 1

section '.idata' import data readable
	library kernel32, 'kernel32.dll', msvcrt, 'msvcrt.dll', Ws2_32, 'Ws2_32.dll',\
		utilities, 'utilities.dll'

	import kernel32, ExitProcess, 'ExitProcess', Sleep, 'Sleep',\
			 OpenFile, 'OpenFile', WriteFile, 'WriteFile',\
			 CloseHandle, 'CloseHandle', ReadFile, 'ReadFile',\
			 InterlockedIncrement, 'InterlockedIncrement',\
			 InterlockedDecrement, 'InterlockedDecrement',\
			 InitializeCriticalSection, 'InitializeCriticalSection',\
			 DeleteCriticalSection, 'DeleteCriticalSection',\
			 EnterCriticalSection, 'EnterCriticalSection',\
			 LeaveCriticalSection, 'LeaveCriticalSection',\
			 GetCurrentDirectoryA, 'GetCurrentDirectoryA',\
			 FindFirstChangeNotificationA, 'FindFirstChangeNotificationA',\
			 FindNextChangeNotification, 'FindNextChangeNotification',\
			 FindCloseChangeNotification, 'FindCloseChangeNotification',\
			 WaitForSingleObject, 'WaitForSingleObject',\
			 GetTickCount, 'GetTickCount'

	import msvcrt, printf, 'printf', _beginthread, '_beginthread',\
		       malloc, 'malloc', calloc, 'calloc', free, 'free',\
		       sprintf, 'sprintf', fopen, 'fopen', fgets, 'fgets',\
		       fclose, 'fclose'

	import utilities, CompressMemory, 'CompressMemory',\
			  GenerateMD5, 'GenerateMD5'

	import Ws2_32, WSAStartup, 'WSAStartup',WSACleanup, 'WSACleanup',\
		       socket, 'socket', closesocket, 'closesocket',\
		       htons, 'htons', ntohs, 'ntohs', bind, 'bind',\
		       listen, 'listen', accept, 'accept', send, 'send',\
		       recv, 'recv', WSAGetLastError, 'WSAGetLastError',\
		       connect, 'connect', htonl, 'htonl',\
		       getaddrinfo, 'getaddrinfo', shutdown, 'shutdown'

section '.edata' export data readable
	export 'Server.dll',\
	       InitializeServer, 'InitializeServer',\
	       ShutdownServer, 'ShutdownServer',\
	       ListenerLoop, 'ListenerLoop'

section '.reloc' fixups data readable discardable