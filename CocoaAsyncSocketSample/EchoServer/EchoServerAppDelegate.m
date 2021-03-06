#import "EchoServerAppDelegate.h"
#import "GCDAsyncSocket.h"
#import "DDLog.h"
#import "DDTTYLogger.h"
#import "Config.h"

#define WELCOME_MSG  0
#define ECHO_MSG     1
#define WARNING_MSG  2

#define READ_TIMEOUT 15.0
#define READ_TIMEOUT_EXTENSION 10.0

#define FORMAT(format, ...) [NSString stringWithFormat:(format), ##__VA_ARGS__]

@interface EchoServerAppDelegate (PrivateAPI)

- (void)logError:(NSString *)msg;
- (void)logInfo:(NSString *)msg;
- (void)logMessage:(NSString *)msg;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation EchoServerAppDelegate{
    NSInteger totolWriteBytes;
}

@synthesize window;

- (id)init
{
	if((self = [super init]))
	{
        totolWriteBytes = 0;
		// Setup our logging framework.
		// Logging isn't used in this file, but can optionally be enabled in GCDAsyncSocket.
		[DDLog addLogger:[DDTTYLogger sharedInstance]];
		
		// Setup our server socket (GCDAsyncSocket).
		// The socket will invoke our delegate methods using the usual delegate paradigm.
		// However, it will invoke the delegate methods on a specified GCD delegate dispatch queue.
		// 
		// Now we can setup these delegate dispatch queues however we want.
		// Here are a few examples:
		// 
		// - A different delegate queue for each client connection.
		// - Simply use the main dispatch queue, so the delegate methods are invoked on the main thread.
		// - Add each client connection to the same dispatch queue.
		// 
		// The best approach for your application will depend upon convenience, requirements and performance.
		// 
		// For this simple example, we're just going to share the same dispatch queue amongst all client connections.
		
//		socketQueue = dispatch_queue_create("SocketQueue", NULL);
        
        socketQueue = dispatch_queue_create("SocketQueue", DISPATCH_QUEUE_SERIAL);
		listenSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:socketQueue];
		
		// Setup an array to store all accepted client connections
		connectedSockets = [[NSMutableArray alloc] initWithCapacity:1];
		
		isRunning = NO;
	}
	return self;
}

- (void)awakeFromNib
{
	[logView setString:@""];
//    int port = [portField intValue];
    [portField setStringValue:[@(kConnectPort) description]];
    portField.enabled = NO;
    
    [self startStop:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Reserved
}

- (void)scrollToBottom
{
	NSScrollView *scrollView = [logView enclosingScrollView];
	NSPoint newScrollOrigin;
	
	if ([[scrollView documentView] isFlipped])
		newScrollOrigin = NSMakePoint(0.0F, NSMaxY([[scrollView documentView] frame]));
	else
		newScrollOrigin = NSMakePoint(0.0F, 0.0F);
	
	[[scrollView documentView] scrollPoint:newScrollOrigin];
}

- (void)logError:(NSString *)msg
{
	NSString *paragraph = [NSString stringWithFormat:@"%@\n", msg];
	
	NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:1];
	[attributes setObject:[NSColor redColor] forKey:NSForegroundColorAttributeName];
	
	NSAttributedString *as = [[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
	[as autorelease];
	
	[[logView textStorage] appendAttributedString:as];
	[self scrollToBottom];
}

- (void)logInfo:(NSString *)msg
{
	NSString *paragraph = [NSString stringWithFormat:@"%@\n", msg];
	
	NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:1];
	[attributes setObject:[NSColor purpleColor] forKey:NSForegroundColorAttributeName];
	
	NSAttributedString *as = [[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
	[as autorelease];
	
	[[logView textStorage] appendAttributedString:as];
	[self scrollToBottom];
}

- (void)logMessage:(NSString *)msg
{
	NSString *paragraph = [NSString stringWithFormat:@"%@\n", msg];
	
	NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:1];
	[attributes setObject:[NSColor blackColor] forKey:NSForegroundColorAttributeName];
	
	NSAttributedString *as = [[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
	[as autorelease];
	
	[[logView textStorage] appendAttributedString:as];
	[self scrollToBottom];
}

- (IBAction)startStop:(id)sender
{
	if(!isRunning)
	{
		int port = [portField intValue];
		
		if(port < 0 || port > 65535)
		{
			[portField setStringValue:@""];
			port = 0;
		}
		
		NSError *error = nil;
		if(![listenSocket acceptOnPort:port error:&error])
		{
			[self logError:FORMAT(@"Error starting server: %@", error)];
			return;
		}
		
		[self logInfo:FORMAT(@"Echo server started on port %hu", [listenSocket localPort])];
		isRunning = YES;
		
		[portField setEnabled:NO];
		[startStopButton setTitle:@"Stop"];
	}
	else
	{
		// Stop accepting connections
		[listenSocket disconnect];
		
		// Stop any client connections
		@synchronized(connectedSockets)
		{
			NSUInteger i;
			for (i = 0; i < [connectedSockets count]; i++)
			{
				// Call disconnect on the socket,
				// which will invoke the socketDidDisconnect: method,
				// which will remove the socket from the list.
				[[connectedSockets objectAtIndex:i] disconnect];
			}
		}
		
		[self logInfo:@"Stopped Echo server"];
		isRunning = false;
		
		[portField setEnabled:YES];
		[startStopButton setTitle:@"Start"];
	}
}


- (IBAction)send:(id)sender{
    GCDAsyncSocket *lastSocket = [connectedSockets lastObject];
    int sendByte = 1024;
    char test[sendByte+1];
    char *p = test;
    for (NSInteger i = 0; i < sendByte; i++) {
        *p = 'a';
        p++;
    }
    *p = '\0';
    
    NSInteger count = 0;
    while (count++ < 1024*1024/sendByte) {//一次发送1K，发送1024次，即1M
        NSString *welcomeMsg = [NSString stringWithCString:test encoding:NSUTF8StringEncoding];
        NSData *welcomeData = [welcomeMsg dataUsingEncoding:NSUTF8StringEncoding];
        [lastSocket writeData:welcomeData withTimeout:-1 tag:WELCOME_MSG];
    }
}



- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
	// This method is executed on the socketQueue (not the main thread)
	
	@synchronized(connectedSockets)
	{
		[connectedSockets addObject:newSocket];
	}
	
	NSString *host = [newSocket connectedHost];
	UInt16 port = [newSocket connectedPort];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		[self logInfo:FORMAT(@"Accepted client %@:%hu", host, port)];
		
		[pool release];
	});
	
//	NSString *welcomeMsg = @"Welcome to the AsyncSocket Echo Server\r\n";
//	NSData *welcomeData = [welcomeMsg dataUsingEncoding:NSUTF8StringEncoding];
//	
//	[newSocket writeData:welcomeData withTimeout:-1 tag:WELCOME_MSG];
//	[newSocket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:READ_TIMEOUT tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
	if (tag == ECHO_MSG)
	{
//		[sock readDataToData:[GCDAsyncSocket CRLFData] withTimeout:READ_TIMEOUT tag:0];
//        totolWriteBytes += sock.writeCount;
	}
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	dispatch_async(dispatch_get_main_queue(), ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		NSData *strData = [data subdataWithRange:NSMakeRange(0, [data length] - 2)];
		NSString *msg = [[[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding] autorelease];
		if (msg)
		{
			[self logMessage:msg];
		}
		else
		{
			[self logError:@"Error converting received data into UTF-8 String"];
		}
		
		[pool release];
	});
	
	// Echo message back to client
	[sock writeData:data withTimeout:-1 tag:ECHO_MSG];
}

/**
 * This method is called if a read has timed out.
 * It allows us to optionally extend the timeout.
 * We use this method to issue a warning to the user prior to disconnecting them.
**/
- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag
                                                                 elapsed:(NSTimeInterval)elapsed
                                                               bytesDone:(NSUInteger)length
{
	if (elapsed <= READ_TIMEOUT)
	{
		NSString *warningMsg = @"Are you still there?Are you still there?Are you still there?Are you still there?Are you still there?Are you still there?\r\n";
		NSData *warningData = [warningMsg dataUsingEncoding:NSUTF8StringEncoding];
		
		[sock writeData:warningData withTimeout:-1 tag:WARNING_MSG];
		
		return READ_TIMEOUT_EXTENSION;
	}
	
	return 0.0;
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	if (sock != listenSocket)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
			
			[self logInfo:FORMAT(@"Client Disconnected")];
			
			[pool release];
		});
		
		@synchronized(connectedSockets)
		{
			[connectedSockets removeObject:sock];
		}
	}
}

@end
