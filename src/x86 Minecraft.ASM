format PE console
entry start

include 'win32a.inc'

section '.text' code executable
start:
	invoke InitializeServer, 25565
	or eax, eax
	jnz close
	invoke Sleep, 100
	cinvoke printf, serverStartedUp

mainLoop:
	cinvoke _beginthread, [ListenerLoop], 0, 0
	cinvoke system, p
	;TODO: add console commands

close:
	cinvoke printf, serverClosing
	invoke ShutdownServer
	invoke Sleep, 1000
	cinvoke system, p
	invoke ExitProcess, 0


section '.rdata' data readable writeable
	d db '%d',10,0
	p db 'pause', 0

	serverStartedUp db 'Server initialized.',10,0
	serverClosing db 'Server is shutting down...',10,0

section '.idata' data readable import
	library kernel32, 'kernel32.dll', msvcrt, 'msvcrt.dll', Server, 'Server.dll'

	import kernel32, Sleep, 'Sleep', ExitProcess, 'ExitProcess'

	import msvcrt, printf, 'printf', system, 'system',\
		       _beginthread, '_beginthread'

	import Server, InitializeServer, 'InitializeServer',\
		       ShutdownServer, 'ShutdownServer',\
		       ListenerLoop, 'ListenerLoop'