;_recv socket, destination, counterReg, flags, bytes to read
macro _recv arg1, arg2, arg3, arg4, arg5 {
	mov arg3, arg5
	@@:
	push arg3
	invoke recv, arg1, arg2, arg3, arg4
	pop arg3
	cmp eax, 0
	jle .error
	sub arg3, eax
	add arg2, eax
	cmp arg3, 0
	jg @b
}

;bool ReadHandshake (SOCKET socket, char* name, char* mppass)
proc ReadHandshake socket, name, mppass
     local buffer rb 131
     push esi
     push edi
     lea esi, [buffer]
     _recv [socket], esi, ecx, 0, 131

     cinvoke printf, esi

     lea esi, [buffer]
     cmp byte [esi], 0	;check packet ID
     jne .error
     cmp byte[esi+1], 7 ;check protocol version
     jne .error

     cld		;copy name from buffer:
     add esi, 2
     mov edi, [name]
     mov ecx, 64
     rep movsb

     mov edi, [mppass]	;move verification key to mppass
     mov ecx, 32
     rep movsb

     pop edi
     pop esi
     mov eax, 0
     ret

 .error:
     pop edi
     pop esi
     mov eax, -1
     ret
endp

;bool ReadBlockPacket(SOCKET socket)
proc ReadBlockPacket socket
    local buffer rb 8
    push ebx
    lea edx, [buffer]
    _recv [socket], edx, ecx, 0, 8

    lea ebx, [buffer]
    mov eax, 0
    mov ecx, 0
    mov edx, 0
    mov ah, [ebx]      ;x
    mov al, [ebx+1]
    mov ch, [ebx+2]    ;notch y (z)
    mov cl, [ebx+3]
    mov dh, [ebx+4]    ;notch z (y)
    mov dl, [ebx+5]

    imul ecx, 256      ;get block index
    add ecx, edx
    imul ecx, 256
    add ecx, eax
    cmp ecx, 4194303   ;check for overflow
    jg .error

    mov eax, 0	       ;check block mode (delete or build)
    mov edx, 0
    mov dl, [ebx+6]
    mov al, [ebx+7]
    imul eax, edx
    push ecx
    push eax
    invoke EnterCriticalSection, worldDataLock
    pop eax
    pop ecx
    mov [worldData+ecx], al    ;update map data
    push eax
    invoke LeaveCriticalSection, worldDataLock
    pop eax
    mov [ebx+6], al
    dec ebx
    mov byte [ebx], 0x06
    stdcall broadcastBlockPacket, ebx

    pop ebx
    mov eax, 0
    ret

  .error:
    pop ebx
    mov eax, -1
    ret
endp

;int ReadPositionPacket(player* p)
;returns -1 if error, 0 if no movement change, 1 if movement change
proc ReadPositionPacket p
    local buffer rb 9
    push ebx
    push esi
    mov esi, [p]
    virtual at esi
       .player Player
    end virtual
    lea ebx, [buffer]
    _recv [.player.socket], ebx, ecx, 0, 9

    lea ebx, [buffer]
    
    mov ax, 0
    mov cx, 0
    mov dx, 0
    mov ah, [ebx+1]
    mov al, [ebx+2]
    mov ch, [ebx+3]
    mov cl, [ebx+4]
    mov dh, [ebx+5]
    mov dl, [ebx+6]
    push ax
    cmp [.player.x], ax
    jne .movement
    cmp [.player.y], dx
    jne .movement
    cmp [.player.z], cx
    jne .movement
    mov al, [ebx+7]
    cmp [.player.yaw], al
    jne .movement
    mov al, [ebx+8]
    cmp [.player.pitch], al
    jne .movement

    pop ax
    pop esi
    pop ebx
    mov eax, 0
    ret

 .movement:
    pop ax
    mov [.player.x], ax
    mov [.player.y], dx
    mov [.player.z], cx
    mov al, [ebx+7]
    mov cl, [ebx+8]
    mov [.player.yaw], al
    mov [.player.pitch], cl
    pop esi
    pop ebx
    mov eax, 1
    ret

 .error:
    pop esi
    pop ebx
    mov eax, -1
    ret
endp

proc ReadMessagePacket player
    local buffer rb 65
    push esi
    push ebx
    mov ebx, [player]
    virtual at ebx
	.p Player
    end virtual
    lea esi, [buffer]
    _recv [.p.socket], esi, ecx, 0, 65

    lea edx, [buffer+1]
    stdcall broadcastMessage, [player], edx

    mov eax, 0
    pop ebx
    pop esi
    ret

  .error:
   mov eax, -1
   pop ebx
   pop esi
   ret
endp













