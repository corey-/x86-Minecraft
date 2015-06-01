struc addrinfo {
   .ai_flags rd 1
   .ai_family rd 1
   .ai_socktype rd 1
   .ai_protocol rd 1
   .ai_addrlen rd 1
   .ai_canonname rd 1
   .ai_addr rd 1
   .ai_next rd 1
}

;void LoopHeartbeat
proc LoopHeartbeat 
     local pathName rb 3000
     local recvBuffer rb 100
     local heartbeatSocket rd 1

     lea ebx, [addrResult]

     virtual at ebx
	.addrI addrinfo
     end virtual

     invoke getaddrinfo, hostName, port80, 0, ebx
     cmp eax, 0
     jne .error

     cinvoke printf, heartbeatInitialized

     mov ebx, [ebx]
.sendloop:
     invoke socket, [.addrI.ai_family], [.addrI.ai_socktype], [.addrI.ai_protocol]
     cmp eax, INVALID_SOCKET
     je .error

     mov [heartbeatSocket], eax

     invoke connect, [heartbeatSocket], [.addrI.ai_addr], [.addrI.ai_addrlen]
     cmp eax, SOCKET_ERROR
     je .error

     lea esi, [pathName]
     cinvoke sprintf, esi, pathTemplate, publicServer, MAX_PLAYERS, [playersCount], [sPort], salt, mcnetName

     invoke send, [heartbeatSocket], esi, eax, 0
     cmp eax, SOCKET_ERROR
     je .error

     invoke shutdown, [heartbeatSocket], 1
     lea esi, [recvBuffer]
  @@:
     invoke recv, [heartbeatSocket], esi, 100, 0

     cmp eax, 0
     jg @b

     invoke closesocket, [heartbeatSocket]
     mov esi, 60
  @@:
     invoke Sleep, 500
     cmp [serverClosing], 1
     je .close
     dec esi
     cmp esi, 0
     jg @b
     jmp .sendloop

 .error:
     invoke WSAGetLastError
     cmp eax, 10060   ;timeout
     je .sendloop
     cinvoke printf, heartbeatError, eax
 .close:
     ret

endp




