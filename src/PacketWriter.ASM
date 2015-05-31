;bool SendHandshakePacket(SOCKET socket)
proc SendHandshakePacket socket
    local buffer rb 131
    push esi
    push edi
    lea eax, [buffer]
    mov byte [eax], 0	      ;packet id
    mov byte [eax+1], 7       ;protocol version
    mov byte [eax+130], 0     ;unused

    cld 		      ;copy server name
    mov esi, serverName
    mov edi, eax
    add edi, 2
    mov ecx, 64
    rep movsb

    mov esi, serverMOTD       ;copy MOTD
    mov ecx, 64
    rep movsb

    invoke send, [socket], eax, 131, 0
    xor eax, 131
    pop edi esi
    ret
endp

;bool SendLevelBeginPacket(SOCKET socket)
proc SendLevelBeginPacket socket
    local buffer rb 1
    lea eax, [buffer]
    mov byte [eax], 2	 ;packet id

    invoke send, [socket], eax, 1, 0
    xor eax, 1
    ret
endp

;bool SendLevelChunkPacket(SOCKET socket, char* data)
proc SendLevelChunkPacket socket, data
    local buffer rb 1028
    push esi
    push edi
    lea eax, [buffer]
    cld 		 ;copy data buffer
    mov esi, [data]
    mov edi, eax
    mov ecx, 1028
    rep movsb

    invoke send, [socket], eax, 1028, 0
    xor eax, 1028
    pop edi esi
    ret
endp

;bool SendLevelEndPacket(SOCKET socket)
proc SendLevelEndPacket socket
    local buffer rb 7
    lea eax, [buffer]
    mov byte [eax], 4	 ;packet id
    mov byte [eax+1], 1  ;256 netorder
    mov byte [eax+2], 0
    mov byte [eax+3], 0  ;64 netorder
    mov byte [eax+4], 64
    mov byte [eax+5], 1  ;256 netorder
    mov byte [eax+6], 0

    invoke send, [socket], eax, 7, 0
    xor eax, 7
    ret
endp

;bool SendSpawnPacket(byte pid, player* from, player* to)
proc SendSpawnPacket pid:BYTE, p, p2
    local buffer rb 74
    push esi edi ebx
    lea eax, [buffer]
    mov byte [eax], 7	 ;packet id
    mov cl, [pid]
    mov [eax+1], cl
    mov ebx, [p]
    virtual at ebx
	.player Player
    end virtual

    cld 		 ;copy name
    lea esi, [.player.name]
    mov edi, eax
    add edi, 2
    mov ecx, 64
    rep movsb

    mov dx, [.player.x]       ;x
    mov [eax+66], dh
    mov [eax+67], dl
    mov dx, [.player.z]       ;notch y (z)
    mov [eax+68], dh
    mov [eax+69], dl
    mov dx, [.player.y]       ;notch z (y)
    mov [eax+70], dh
    mov [eax+71], dl
    mov dl, [.player.yaw]
    mov [eax+72], dl
    mov dl, [.player.pitch]
    mov [eax+73], dl
    mov ebx, [p2]
    lea edi, [.player.socketLock]
    push eax
    invoke EnterCriticalSection, edi
    pop eax
    invoke send, [.player.socket], eax, 74,0
    push eax
    invoke LeaveCriticalSection, edi
    pop eax
    xor eax, 74
    pop ebx edi esi
    ret
endp

;bool SendTeleportPacket (int pid, player* from, player* to)
proc SendTeleportPacket pid, p, p2
     local buffer rb 10
     push ebx esi edi

     lea ebx, [buffer]
     mov byte [ebx], 0x08   ;packet id
     mov eax, [pid]
     mov [ebx+1], al	    ;pid

     mov esi, [p]
     virtual at esi
	 .player Player
     end virtual

     movzx eax, [.player.x]    ;x
     invoke htons, eax
     mov [ebx+2], ax
     movzx eax, [.player.z]    ;notch y (z)
     invoke htons, eax
     mov [ebx+4], ax
     movzx eax, [.player.y]    ;notch z (y)
     invoke htons, eax
     mov [ebx+6], ax
     mov al, [.player.yaw]
     mov [ebx+8], al
     mov al, [.player.pitch]
     mov [ebx+9], al

     mov esi, [p2]
     cmp [.player.loadingWorld], 1
     jne @f
     mov eax, 0
     ret
  @@:
     lea edi, [.player.socketLock]
     invoke EnterCriticalSection, edi
     invoke send, [.player.socket], ebx, 10, 0
     push eax
     invoke LeaveCriticalSection, edi
     pop eax
     xor eax, 10
     pop edi esi ebx
     ret
endp

;void SendDespawnPacket(byte pid, player* p)
proc SendDespawnPacket pid:BYTE, p
     local buffer rd 2
     push ebx esi edi

     lea edi, [buffer]
     mov byte [edi], 0x0c	       ;packet id
     mov al, [pid]		       ;player id
     mov [edi+1], al

     mov esi, [p]
     virtual at esi
	.player Player
     end virtual

     lea ebx, [.player.socketLock]
     invoke EnterCriticalSection, ebx
     invoke send, [.player.socket], edi, 2, 0
     invoke LeaveCriticalSection, ebx

     pop edi esi ebx
     ret
endp

;bool SendDisconnectPacket(SOCKET socket, char* reason)
proc SendDisconnectPacket socket, reason
     local buffer rb 65
     mov [buffer], 0x0e        ;packet id
     mov eax, [reason]
     mov ecx, 1

 .copy: 		       ;copy reason to buffer
     cmp byte [eax+ecx-1], 0   ;break at null character
     je .pad
     mov bl, [eax+ecx-1]
     mov [buffer+ecx], bl
     inc ecx
     cmp ecx, 65
     je .send
     jmp .copy

 .pad:			       ;pad with spaces as per protocol
     mov [buffer+ecx], 0x20
     inc ecx
     cmp ecx, 65
     je .send
     jmp .pad

 .send: 		       ;send to player
     lea eax, [buffer]
     invoke send, [socket], eax, 65, 0
     xor eax, 65
     ret
endp

;bool SendExtInfoPacket (SOCKET socket)
proc SendExtInfoPacket socket
     local buffer rb 67
     mov [buffer], 0x10        ;packet id
     mov esi, serverName
     lea edi, [buffer+1]
     mov ecx, 64
     rep movsb
     mov eax, [exts]
     mov [buffer+65], 0
     mov [buffer+66], 1

     lea eax, [buffer]
     invoke send, [socket], eax, 67, 0
     xor eax, 67
     ret
endp

;bool SendExtEntryPacket(SOCKET socket, char* extname)
proc SendExtEntryPackets socket
     local buffer rb 69
     mov [buffer], 0x11       ;packet id

     ; custom blocks
     mov esi, customBlocks
     lea edi, [buffer+1]
     mov ecx, 64
     rep movsb
     mov [buffer+65], 0
     mov [buffer+66], 0
     mov [buffer+67], 0
     mov [buffer+68], 1
     lea eax, [buffer]
     invoke send, [socket], eax, 69, 0
     xor eax, 69
     jnz .done

 .done:
     ret
endp