//
//  RNClientWrapper.m
//  RNStringee
//
//  Created by HoangDuoc on 5/20/20.
//

#import "RNClientWrapper.h"
#import "RNStringeeInstanceManager.h"
#import "RNStringeeClient.h"
#import "RCTConvert+StringeeHelper.h"

@implementation RNClientWrapper {
    NSMutableArray<NSString *> *jsEvents;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    self = [super init];
    if (self) {
        self.identifier = identifier;
        jsEvents = [[NSMutableArray alloc] init];
        _messages = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_client disconnect];
    _client = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setNativeEvent:(NSString *)event {
    [jsEvents addObject:event];
}

- (void)removeNativeEvent:(NSString *)event {
    int index = -1;
    index = (int)[jsEvents indexOfObject:event];
    if (index >= 0) {
        [jsEvents removeObjectAtIndex:index];
    }
}

- (void)createClientIfNeed {
    if (!_client) {
        _client = [[StringeeClient alloc] initWithConnectionDelegate:self];
        _client.incomingCallDelegate = self;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleObjectChangeNotification:) name:StringeeClientObjectsDidChangeNotification object:_client];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessageNotification:) name:StringeeClientNewMessageNotification object:_client];
    }
}

#pragma mark Connection Delelgate

- (void)requestAccessToken:(StringeeClient *)stringeeClient {
    _isConnecting = NO;
    [RNStringeeInstanceManager.instance.rnClient sendEventWithName:requestAccessToken body: @{ @"uuid" : _identifier, @"data" : @{ @"userId" : stringeeClient.userId}}];
}

- (void)didConnect:(StringeeClient *)stringeeClient isReconnecting:(BOOL)isReconnecting {
    if ([jsEvents containsObject:didConnect]) {
        [RNStringeeInstanceManager.instance.rnClient sendEventWithName:didConnect body: @{ @"uuid" : _identifier, @"data" : @{ @"userId" : stringeeClient.userId, @"projectId" : stringeeClient.projectId, @"isReconnecting" : @(isReconnecting) } }];
    }
}

- (void)didDisConnect:(StringeeClient *)stringeeClient isReconnecting:(BOOL)isReconnecting {
    if ([jsEvents containsObject:didDisConnect]) {
        [RNStringeeInstanceManager.instance.rnClient sendEventWithName:didDisConnect body: @{ @"uuid" : _identifier, @"data" : @{ @"userId" : stringeeClient.userId, @"projectId" : stringeeClient.projectId, @"isReconnecting" : @(isReconnecting) }}];
    }
}

- (void)didFailWithError:(StringeeClient *)stringeeClient code:(int)code message:(NSString *)message {
    if ([jsEvents containsObject:didFailWithError]) {
        [RNStringeeInstanceManager.instance.rnClient sendEventWithName:didFailWithError body: @{ @"uuid" : _identifier, @"data" : @{ @"userId" : stringeeClient.userId, @"code" : @(code), @"message" : message }}];
    }
}

- (void)didReceiveCustomMessage:(StringeeClient *)stringeeClient message:(NSDictionary *)message fromUserId:(NSString *)userId {
    if ([jsEvents containsObject:didReceiveCustomMessage]) {
        NSString *data;
        if (message) {
            NSError *err;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message options:0 error:&err];
            data = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
        
        data = (data != nil) ? data : @"";
        
        [RNStringeeInstanceManager.instance.rnClient sendEventWithName:didReceiveCustomMessage body: @{ @"uuid" : _identifier, @"data" : @{ @"from" : userId, @"data" : data }}];
    }
}

#pragma mark Call Delelgate

- (void)incomingCallWithStringeeClient:(StringeeClient *)stringeeClient stringeeCall:(StringeeCall *)stringeeCall {
    [[RNStringeeInstanceManager instance].calls setObject:stringeeCall forKey:stringeeCall.callId];

    if ([jsEvents containsObject:incomingCall]) {

        int index = 0;

        if (stringeeCall.callType == CallTypeCallIn) {
            // Phone-to-app
            index = 3;
        } else if (stringeeCall.callType == CallTypeCallOut) {
            // App-to-phone
            index = 2;
        } else if (stringeeCall.callType == CallTypeInternalIncomingCall) {
            // App-to-app-incoming-call
            index = 1;
        } else {
            // App-to-app-outgoing-call
            index = 0;
        }

        id returnUserId = stringeeClient.userId ? stringeeClient.userId : [NSNull null];
        id returnCallId = stringeeCall.callId ? stringeeCall.callId : [NSNull null];
        id returnFrom = stringeeCall.from ? stringeeCall.from : [NSNull null];
        id returnTo = stringeeCall.to ? stringeeCall.to : [NSNull null];
        id returnFromAlias = stringeeCall.fromAlias ? stringeeCall.fromAlias : [NSNull null];
        id returnToAlias = stringeeCall.toAlias ? stringeeCall.toAlias : [NSNull null];
        id returnCustomData = stringeeCall.customDataFromYourServer ? stringeeCall.customDataFromYourServer : [NSNull null];

        [RNStringeeInstanceManager.instance.rnClient sendEventWithName:incomingCall body: @{ @"uuid" : _identifier, @"data" : @{ @"userId" : returnUserId, @"callId" : returnCallId, @"from" : returnFrom, @"to" : returnTo, @"fromAlias" : returnFromAlias, @"toAlias" : returnToAlias, @"callType" : @(index), @"isVideoCall" : @(stringeeCall.isVideoCall), @"customDataFromYourServer" : returnCustomData}}];
    }
    
}

#pragma mark Handle chat event

- (void)handleObjectChangeNotification:(NSNotification *)notification {
    if (![jsEvents containsObject:objectChangeNotification]) return;

    NSArray *objectChanges = [notification.userInfo objectForKey:StringeeClientObjectChangesUserInfoKey];
    if (!objectChanges.count) {
        return;
    }

    NSMutableArray *objects = [[NSMutableArray alloc] init];

    for (StringeeObjectChange *objectChange in objectChanges) {
        [objects addObject:objectChange.object];
    }

    StringeeObjectChange *firstObjectChange = [objectChanges firstObject];
    id firstObject = [objects firstObject];

    int objectType;
    NSArray *jsObjectDatas;
    if ([firstObject isKindOfClass:[StringeeConversation class]]) {
        objectType = 0;
        jsObjectDatas = [RCTConvert StringeeConversations:objects];
    } else if ([firstObject isKindOfClass:[StringeeMessage class]]) {
        objectType = 1;
        jsObjectDatas = [RCTConvert StringeeMessages:objects];

        // Xo?? ?????i t?????ng message ???? l??u
        for (NSDictionary *message in jsObjectDatas) {
            NSNumber *state = message[@"state"];
            if (state.intValue == StringeeMessageStatusRead) {
                NSString *localId = message[@"localId"];
                if (localId) {
                    [_messages removeObjectForKey:localId];
                }
            }
        }
    } else {
        objectType = 2;
    }

    id returnObjects = jsObjectDatas ? jsObjectDatas : [NSNull null];

    [RNStringeeInstanceManager.instance.rnClient sendEventWithName:objectChangeNotification body: @{ @"uuid" : _identifier, @"data" : @{ @"objectType" : @(objectType), @"objects" : returnObjects, @"changeType" : @(firstObjectChange.type) }}];
}

- (void)handleNewMessageNotification:(NSNotification *)notification {
    if (![jsEvents containsObject:objectChangeNotification]) return;

    NSDictionary *userInfo = [notification userInfo];
    if (!userInfo) return;
    
    NSString *convId = [userInfo objectForKey:StringeeClientNewMessageConversationIDKey];
    if (convId == nil || convId.length == 0) {
        return;
    }
    
    // L???y v??? conversation
    __weak RNClientWrapper *weakSelf = self;
    [_client getConversationWithConversationId:convId completionHandler:^(BOOL status, int code, NSString *message, StringeeConversation *conversation) {
        if (!conversation) {
            return;
        }
        
        if (weakSelf == nil) {
            return;
        }

        RNClientWrapper *strongSelf = weakSelf;
        [RNStringeeInstanceManager.instance.rnClient sendEventWithName:objectChangeNotification body: @{ @"uuid" : strongSelf.identifier, @"data" : @{ @"objectType" : @(0), @"objects" : @[[RCTConvert StringeeConversation:conversation]], @"changeType" : @(StringeeObjectChangeTypeCreate) }}];
    }];
}

@end
