#!/usr/local/bin/php -q
<?php
	
//a little bit of fun with a socket server

error_reporting(E_ALL);

/* Allow the script to hang around waiting for connections. */
set_time_limit(0);

/* Turn on implicit output flushing so we see what we're getting
 * as it comes in. */
ob_implicit_flush();

$address = '0.0.0.0';
$port = 23;

if (($sock = socket_create(AF_INET, SOCK_STREAM, SOL_TCP)) === false) {
    echo "socket_create() failed: reason: " . socket_strerror(socket_last_error()) . "\n";
    die();
}

if (socket_bind($sock, $address, $port) === false) {
    echo "socket_bind() failed: reason: " . socket_strerror(socket_last_error($sock)) . "\n";
    die();
}

if (socket_listen($sock, 5) === false) {
    echo "socket_listen() failed: reason: " . socket_strerror(socket_last_error($sock)) . "\n";
    die();
}


//clients array
$clients = array();

do {
    
    $read = array();
    $read[] = $sock;
    
    $read = array_merge($read,$clients);
    
    $write = NULL;
    $except = NULL;
    
    // Set up a blocking call to socket_select
    if(socket_select($read,$write, $except, $tv_sec = 5) < 1)
    {
        //    SocketServer::debug("Problem blocking socket_select?");
        continue;
    }
    
    // Handle new Connections
    if (in_array($sock, $read)) {   
    
	    if (($msgsock = socket_accept($sock)) === false) {
	        echo "socket_accept() failed: reason: " . socket_strerror(socket_last_error($sock)) . "\n";
	        break;
	    }
	    
	    $clients[] = $msgsock;
        $key = array_keys($clients, $msgsock);
    
		$msg="Connected\n";
    
		socket_write($msgsock, $msg, strlen($msg));
    
		/* Send instructions. */
		//$msg = "\nWelcome to the PHP Test Server. \n" .
        	"To quit, type 'quit'. To shut down the server type 'shutdown'.\n";
		//socket_write($msgsock, $msg, strlen($msg));
	}
	
	
	foreach ($clients as $key => $client) { // for each client        
        if (in_array($client, $read)) {
            if (false === ($buf = socket_read($client, 2048, PHP_NORMAL_READ))) {
                echo "socket_read() falló: razón: " . socket_strerror(socket_last_error($client)) . "\n";
                break 2;
            }
            if (!$buf = trim($buf)) {
                continue;
            }
            if ($buf == 'quit') {
                unset($clients[$key]);
                socket_close($client);
                break;
            }
            if ($buf == 'shutdown') {
                socket_close($client);
                break 2;
            }

            include('commands.php');

            if($talkback) {
                echo "Me: ".$talkback."\n";
                socket_write($client, $talkback, strlen($talkback));
            }
	        
	        
            }
        
    } 
	
} while (true);

socket_close($sock);
?>