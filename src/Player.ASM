include 'PacketReader.asm'

proc PlayerLoop index
     local dataBuffer rb 50
     local player Player

     mov eax, [clientSocket]
     mov [player.socket], eax
     mov ecx, [index]
     lea eax, [player]
     mov [players+ecx*4], eax

     invoke InterlockedIncrement, playersCount
     lea eax, [player.socketLock]
     invoke InitializeCriticalSection, eax

     cinvoke malloc, 4194308  ;room for map
     cmp eax, 0
     je .close
     mov esi, eax

     invoke EnterCriticalSection, worldDataLock
     cinvoke CompressMemory, worldSize, 4194308, esi
     mov ebx, eax
     invoke LeaveCriticalSection, worldDataLock

     ;Receive/send handshake
     lea eax, [player.name]
     lea ecx, [dataBuffer]
     stdcall ReadHandshake, [player.socket], eax, ecx
     cmp eax, 0
     jne .close

     push esi
     push edi
     lea esi, [player.name]	  ;make null terminated name for console output
     lea edi, [player.namez]	  ;and verification check
     mov ecx, 0
  @@:
     cmp byte [esi], 32
     je @f
     movsb
     inc ecx
     cmp ecx, 64
     jl @b
  @@:
     mov byte [edi], 0
     pop edi
     pop esi

     lea eax, [player.namez]	  ;verify username
     lea ecx, [dataBuffer]
     stdcall verifyUsername, eax, ecx
     cmp eax, 0
     je @f
     stdcall SendDisconnectPacket, [player.socket], playerInvalidPass
     jmp .close

  @@:
     invoke EnterCriticalSection, banlistLock	      ;check the ban list
     lea eax, [player.namez]
     stdcall BanlistContains, eax
     cmp eax, -1
     je .notbanned
     invoke LeaveCriticalSection, banlistLock
     stdcall SendDisconnectPacket, [player.socket], playerBanned
     jmp .close
  .notbanned:
     invoke LeaveCriticalSection, banlistLock

     stdcall SendHandshakePacket, [player.socket]
     cmp eax, 0
     jne .close

     ;Start sending map
     stdcall SendLevelBeginPacket, [player.socket]
     cmp eax, 0
     jne .close

     ;send chunks
     mov edi, esi
  @@:
     stdcall SendLevelChunkPacket, [player.socket], edi
     cmp eax, 0
     jne .close
     add edi, 1028
     dec ebx
     cmp ebx, 0
     jg @b

     cinvoke free, esi

     ;finish level send
     stdcall SendLevelEndPacket, [player.socket]
     cmp eax, 0
     jne .close

     mov [player.loadingWorld], 0
     lea eax, [player.namez]
     cinvoke printf, playerConnected, eax

     ;send spawn self
     lea eax, [player]
     stdcall SendSpawnPacket, 255, eax, eax
     cmp eax, 0
     jne .close

     ;send any packets from queue
     mov ecx, 0
     lea esi, [player.socketLock]
     invoke EnterCriticalSection, esi
     lea ebx, [player.blockPacketQueue]
  @@:
     cmp byte [ebx], 0
     je @f
     invoke send, [player.socket], ebx, 8, 0
     add ebx, 8
     inc ecx
     cmp ecx, 50
     jl @b
  @@:
     invoke LeaveCriticalSection, esi
     mov ecx, 0 		;send spawn packets for other players

     lea esi, [player]
   @@:
     cmp ecx, [index]
     je .sp
     mov ebx, [players+ecx*4]
     cmp ebx, 0
     je .sp
     push ecx
     stdcall SendSpawnPacket, ecx, ebx, esi	   ;send their spawn to me
     stdcall SendSpawnPacket, [index], esi, ebx    ;send my spawn to them
     pop ecx
     cmp eax, 0
     jne .close
  .sp:
     inc ecx
     cmp ecx, 20
     jl @b

     ;begin main I/O loop
  .IOLoop:
     cmp [player.banned], 1
     jne @f
     stdcall SendDisconnectPacket, [player.socket], playerBanned
     jmp .close
  @@:
     lea ebx, [dataBuffer]
     invoke recv, [player.socket], ebx, 1, 0
     cmp eax, 0
     jle .close

     mov al, [dataBuffer]

     cmp al, 0x01    ;ping
     je .IOLoop

     cmp al, 0x08    ;position
     jne @f
     lea eax, [player]
     stdcall ReadPositionPacket, eax
     cmp eax, 0
     je .IOLoop
     cmp eax, -1
     je .close
     lea eax, [player]
     stdcall broadcastMovement, eax, [index]
     jmp .IOLoop

  @@:
     cmp al, 0x05    ;block
     jne @f
     stdcall ReadBlockPacket, [player.socket]
     cmp eax, 0
     je .IOLoop
     jmp .close

  @@:
     cmp al, 0x0d   ;message
     jne @f
     lea eax, [player]
     stdcall ReadMessagePacket, eax
     cmp eax, 0
     je .IOLoop

  @@:
     jmp .close

  .close:
     mov ecx, [index]
     mov [players+ecx*4], 0

     mov ecx, 0 		;send despawn packets to other players
   @@:
     mov ebx, [players+ecx*4]
     cmp ebx, 0
     je .dp
     push ecx
     stdcall SendDespawnPacket, [index], ebx
     pop ecx
  .dp:
     inc ecx
     cmp ecx, 20
     jl @b

     invoke InterlockedDecrement, playersCount
     lea eax, [player.socketLock]
     invoke DeleteCriticalSection, eax
     invoke closesocket, [player.socket]
     lea eax, [player.namez]
     cinvoke printf, playerDisconnected, eax
     ret
endp