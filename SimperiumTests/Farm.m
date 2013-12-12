//
//  Farm.m
//  Simperium
//
//  Created by Michael Johnston on 11-11-10.
//  Copyright (c) 2011 Simperium. All rights reserved.
//

#import "Farm.h"
#import "TestParams.h"
#import "SPUser.h"
#import "SPBucket+Internals.h"
#import "Simperium+Internals.h"

#import "Config.h"
#import "Post.h"
#import "PostComment.h"

@implementation Farm
@synthesize managedObjectContext		= __managedObjectContext;
@synthesize managedObjectModel			= __managedObjectModel;
@synthesize persistentStoreCoordinator	= __persistentStoreCoordinator;


-(id)initWithToken:(NSString *)aToken label:(NSString *)label
{
    if (self = [super init]) {
        self.done = NO;
        
        self.simperium = [[Simperium alloc] initWithRootViewController:nil];
        
        // Setting a label allows each Simperium instance to store user prefs under a different key
        // (be sure to do this before the call to clearLocalData)
        self.simperium.label = label;
        
        [self.simperium setAuthenticationEnabled:NO];
        [self.simperium setVerboseLoggingEnabled:YES];
        self.token = aToken;
    }
    return self;
}

-(void)start
{
    // JSON testing
    //[simperium startWithAppName:APP_ID APIKey:API_KEY];
    
    // Core Data testing
    [self.simperium startWithAppID:APP_ID
							APIKey:API_KEY
							 model:[self managedObjectModel]
						   context:[self managedObjectContext]
					   coordinator:[self persistentStoreCoordinator]];
    
    [self.simperium setAllBucketDelegates: self];
    
    self.simperium.user = [[SPUser alloc] initWithEmail:USERNAME token:self.token];
	
	NSArray *buckets = @[ [Config entityName], [Post entityName], [PostComment entityName] ];
    for (NSString *bucketName in buckets) {
        SPBucket *bucket = [self.simperium bucketForName:bucketName];
        bucket.notifyWhileIndexing = YES;
        
        // Clear data from previous tests if necessary
        [bucket.network resetBucketAndWait:bucket];
    }
}

-(void)stop
{
	[self.simperium removeRemoteData];
	[self waitForCompletion:1.0f];
	[self.simperium signOutAndRemoveLocalData:YES];
}

-(BOOL)waitForCompletion:(NSTimeInterval)timeoutSecs
{
	NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeoutSecs];
    
	do {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:timeoutDate];
		if([timeoutDate timeIntervalSinceNow] < 0.0) {
			break;
		}
	} while (!self.done);
    
	return self.done;
}

-(BOOL)isDone
{
    return self.expectedAcknowledgments == 0 && self.expectedChanges == 0 && self.expectedAdditions == 0 && self.expectedDeletions == 0
        && self.expectedVersions == 0 && self.expectedIndexCompletions == 0;
}

-(void)resetExpectations
{
    self.expectedAcknowledgments = 0;
    self.expectedAdditions = 0;
    self.expectedChanges = 0;
    self.expectedDeletions = 0;
    self.expectedVersions = 0;
    self.expectedIndexCompletions = 0;
}

-(void)logUnfulfilledExpectations
{
    if (![self isDone]) {
        NSLog(@"[%@] acks: %d changes: %d adds: %d dels: %d idxs: %d", self.simperium.label, self.expectedAcknowledgments, self.expectedChanges,
			  self.expectedAdditions, self.expectedDeletions, self.expectedIndexCompletions);
	}
}

-(void)connect
{
    [self.simperium performSelector:@selector(startNetworkManagers)];
}

-(void)disconnect
{
    [self.simperium performSelector:@selector(stopNetworkManagers)];
}

-(void)bucket:(SPBucket *)bucket didChangeObjectForKey:(NSString *)key forChangeType:(SPBucketChangeType)change memberNames:(NSArray *)memberNames
{
    switch(change) {
        case SPBucketChangeAcknowledge:
            self.expectedAcknowledgments -= 1;
//            NSLog(@"%@ acknowledged (%d)", simperium.label, expectedAcknowledgments);
            break;
        case SPBucketChangeDelete:
            self.expectedDeletions -= 1;
//            NSLog(@"%@ received deletion (%d)", simperium.label, expectedDeletions);
            break;
        case SPBucketChangeInsert:
            self.expectedAdditions -= 1;
            break;
        case SPBucketChangeUpdate:
            self.expectedChanges -= 1;
			break;
		case SPBucketChangeMove:
// TODO: Implement!
			break;
    }
}

-(void)bucket:(SPBucket *)bucket willChangeObjectsForKeys:(NSSet *)keys
{
    
}

-(void)bucketWillStartIndexing:(SPBucket *)bucket
{

}

-(void)bucketDidFinishIndexing:(SPBucket *)bucket
{
    NSLog(@"Simperium bucketDidFinishIndexing: %@", bucket.name);
    
    // These aren't always used in the tests, so only decrease it if it's been set
    if (self.expectedIndexCompletions > 0) {
        self.expectedIndexCompletions -= 1;
	}
}

-(void)bucketDidAcknowledgeDelete:(SPBucket *)bucket
{
    self.expectedAcknowledgments -= 1;
//    NSLog(@"%@ acknowledged deletion (%d)", simperium.label, expectedAcknowledgments);
}

-(void)bucket:(SPBucket *)bucket didReceiveObjectForKey:(NSString *)key version:(NSString *)version data:(NSDictionary *)data
{
    self.expectedVersions -= 1;
}


#pragma mark - Manual Core Data stack

// This code for setting up a Core Data stack is taken directly from Apple's Core Data project template.

-(void)saveContext
{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil)
    {
        BOOL bChanged = [managedObjectContext hasChanges];
        if (bChanged && ![managedObjectContext save:&error])
        {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        } 
    }
}

/**
 Returns the managed object context for the application.
 If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
 */
-(NSManagedObjectContext *)managedObjectContext
{
    if (__managedObjectContext != nil)
    {
        return __managedObjectContext;
    }
	__managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    return __managedObjectContext;
}

/**
 Returns the managed object model for the application.
 If the model doesn't already exist, it is created from the application's model.
 */
-(NSManagedObjectModel *)managedObjectModel
{
    if (__managedObjectModel != nil)
    {
        return __managedObjectModel;
    }
    __managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:[NSBundle allBundles]];   
    return __managedObjectModel;
}

/**
 Returns the persistent store coordinator for the application.
 If the coordinator doesn't already exist, it is created and the application's store added to it.
 */
-(NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    // Use an in-memory store for testing
    if (!__persistentStoreCoordinator) {
        NSError *error = nil;
        __persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
        [__persistentStoreCoordinator addPersistentStoreWithType:NSInMemoryStoreType 
                                                   configuration:nil URL:nil options:nil error:&error];
    }
    return __persistentStoreCoordinator;  
}

@end
