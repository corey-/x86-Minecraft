align 4
proc WatchBanlist arglist
    local buffer rb 261
    lea ebx, [buffer]
    invoke GetCurrentDirectoryA, 261, ebx
    cld
    mov esi, banFolder
    mov edi, ebx
    add edi, eax
    mov ecx, 9
    rep movsb

    invoke FindFirstChangeNotificationA, ebx, 0, FILE_NOTIFY_CHANGE_LAST_WRITE
    cmp eax, INVALID_HANDLE_VALUE
    je .error
    mov [fileChangeHandle], eax

    mov esi, banFile
    dec edi
    mov ecx, 13
    rep movsb

    stdcall UpdateBanlist, ebx

.waitloop:
    invoke WaitForSingleObject, [fileChangeHandle], 1000
    cmp [serverClosing], 1
    je .close
    cmp eax, WAIT_TIMEOUT
    je .waitloop
    cmp eax, WAIT_FAILED
    je .error

    stdcall DeleteBanlist
    stdcall UpdateBanlist, ebx
    cmp eax, -1
    je .error

    invoke FindNextChangeNotification, [fileChangeHandle]
    cmp eax, 0
    je .error
    invoke Sleep, 500
    jmp .waitloop

.error:
    cinvoke printf, banWatchError
.close:
    invoke FindCloseChangeNotification, [fileChangeHandle]
    ret
endp

proc UpdateBanlist file
    local buffer rb 64
    local fileHnd rd 1
    push ebx
    cmp [changeFlag], 0 		  ;some reason last write gets
    je @f				  ;modified twice with each save,
    dec [changeFlag]			  ;use flag to update only once
    pop ebx
    ret
 @@:
    inc [changeFlag]
    cinvoke printf, banlistModified

    cinvoke fopen, [file], fileread
    cmp eax, 0
    jne @f
    mov eax, -1
    pop ebx
    ret
 @@:
    mov [fileHnd], eax
    lea ebx, [buffer]
    invoke EnterCriticalSection, banlistLock
 @@:
    cinvoke fgets, ebx, 64, [fileHnd]
    cmp eax, 0
    je @f
    stdcall AddToBanlist, ebx
    jmp @b
 @@:
    invoke LeaveCriticalSection, banlistLock
    cinvoke fclose, [fileHnd]
    cinvoke printf, banlistLoaded, [banlist.size]
    cmp [banlist.size], 0
    je .done

    virtual at ebx
       .player Player
    end virtual
    mov ecx, 0				 ;kick banned players if online
 .loop:
    mov ebx, [players+ecx*4]
    cmp ebx, 0
    je @f
    lea eax, [.player.namez]
    stdcall BanlistContains, eax
    cmp eax, -1
    je @f
    mov [.player.banned], 1
 @@:
    inc ecx
    cmp ecx, 20
    jl .loop

 .done:
    pop ebx
    mov eax, 0
    ret
endp

;########################################################
;Banlist functions
proc DeleteBanlist
    push ebx
    push esi
    mov ebx, [banlist.first]

    virtual at ebx
       .node BanlistNode
    end virtual

    cmp ebx, 0
    je @f

    mov [banlist.first], 0

 .del:
    mov esi, [.node.next]
    cinvoke free, ebx
    mov [.node.next], 0
    cmp esi, 0
    je @f
    mov ebx, esi
    jmp .del

 @@:
    mov [banlist.size], 0
    pop esi
    pop ebx
    ret
endp

proc AddToBanlist name
    mov eax, [name]
    mov al, [eax]
    cmp al, 48
    jge @f
    ret
 @@:
    push ebx
    push esi
    push edi
    lea ebx, [banlist.first]
    virtual at ebx
       .node BanlistNode
    end virtual

    cmp dword [ebx], 0
    je .add

 .loop: 		    ;find last node
    mov ebx, [ebx]
    lea ebx, [.node.next]
    cmp dword [ebx], 0
    je .add
    jmp .loop

 .add:			   ;add node
    cinvoke calloc, 1, sizeBanNode
    cmp eax, 0
    je .add

    mov [ebx], eax
    mov ebx, eax

    cld 		   ;copy name
    mov esi, [name]
    lea edi, [.node.name]
    mov ecx, 64
 @@:
    movsb
    cmp byte [esi], 48
    jl @f
    dec ecx
    cmp ecx, 0
    jg @b
 @@:
    inc [banlist.size]
    pop edi
    pop esi
    pop ebx
    ret
endp

proc BanlistContains name
    push ebx
    push esi
    push edi
    mov ebx, [banlist.first]
    virtual at ebx
       .node BanlistNode
    end virtual

    cmp ebx, 0
    je .no

    cld
 .next:
    mov esi, [name]
    lea edi, [.node.name]
 .loop:
    cmpsb
    jne @f
    cmp byte [esi-1], 0
    je .yes
    jmp .loop
 @@:
    mov ebx, [.node.next]
    cmp ebx, 0
    je .no
    jmp .next

 .yes:
    mov eax, 0
    pop edi
    pop esi
    pop ebx
    ret

 .no:
    mov eax, -1
    pop edi
    pop esi
    pop ebx
    ret
endp



















