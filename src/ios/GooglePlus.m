#import "AppDelegate.h"
#import "objc/runtime.h"
#import "GooglePlus.h"

@implementation GooglePlus

- (void)pluginInitialize
{
    NSLog(@"GooglePlus pluginInitizalize");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURL:) name:CDVPluginHandleOpenURLNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURLWithAppSourceAndAnnotation:) name:CDVPluginHandleOpenURLWithAppSourceAndAnnotationNotification object:nil];
}

- (void)handleOpenURL:(NSNotification*)notification
{
    // no need to handle this handler, we dont have an sourceApplication here, which is required by GIDSignIn handleURL
}

- (void)handleOpenURLWithAppSourceAndAnnotation:(NSNotification*)notification
{
    NSMutableDictionary * options = [notification object];

    NSURL* url = options[@"url"];

    NSString* possibleReversedClientId = [url.absoluteString componentsSeparatedByString:@":"].firstObject;

    if ([possibleReversedClientId isEqualToString:self.getreversedClientId] && self.isSigningIn) {
        self.isSigningIn = NO;
        [[GIDSignIn sharedInstance] handleURL:url];
    }
}

// If this returns false, you better not call the login function because of likely app rejection by Apple,
// see https://code.google.com/p/google-plus-platform/issues/detail?id=900
// Update: should be fine since we use the GoogleSignIn framework instead of the GooglePlus framework
- (void) isAvailable:(CDVInvokedUrlCommand*)command {
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) login:(CDVInvokedUrlCommand*)command {
    _callbackId = command.callbackId;
    NSDictionary* options = command.arguments[0];
    NSString *reversedClientId = [self getreversedClientId];

    if (reversedClientId == nil) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Could not find REVERSED_CLIENT_ID url scheme in app .plist"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
        return;
    }

    NSString *clientId = [self reverseUrlScheme:reversedClientId];
    NSString* serverClientId = options[@"webClientId"];
    NSString* hostedDomain = options[@"hostedDomain"];

    GIDConfiguration *config = [[GIDConfiguration alloc] initWithClientID:clientId serverClientID:serverClientId hostedDomain:hostedDomain openIDRealm:nil];

    GIDSignIn *signIn = [GIDSignIn sharedInstance];

    [signIn signInWithConfiguration:config presentingViewController:self.viewController callback:^(GIDGoogleUser * _Nullable user, NSError * _Nullable error) {
        [self handleSignInCompleteWithUser:user error:error];
    }];
}

- (void) trySilentLogin:(CDVInvokedUrlCommand*)command {
    _callbackId = command.callbackId;
    GIDSignIn *signIn = [GIDSignIn sharedInstance];
    [signIn restorePreviousSignInWithCallback:^(GIDGoogleUser * _Nullable user, NSError * _Nullable error) {
        [self handleSignInCompleteWithUser:user error:error];
    }];
}

- (void) handleSignInCompleteWithUser:(GIDGoogleUser * _Nullable)user error:(NSError * _Nullable)error {
    if (error) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
    } else {
        NSString *email = user.profile.email;
        NSString *idToken = user.authentication.idToken;
        NSString *accessToken = user.authentication.accessToken;
        NSString *refreshToken = user.authentication.refreshToken;
        NSString *userId = user.userID;
        NSString *serverAuthCode = user.serverAuthCode != nil ? user.serverAuthCode : @"";
        NSURL *imageUrl = [user.profile imageURLWithDimension:120]; // TODO pass in img size as param, and try to sync with Android
        NSDictionary *result = @{
                       @"email"           : email,
                       @"idToken"         : idToken,
                       @"serverAuthCode"  : serverAuthCode,
                       @"accessToken"     : accessToken,
                       @"refreshToken"    : refreshToken,
                       @"userId"          : userId,
                       @"displayName"     : user.profile.name       ? : [NSNull null],
                       @"givenName"       : user.profile.givenName  ? : [NSNull null],
                       @"familyName"      : user.profile.familyName ? : [NSNull null],
                       @"imageUrl"        : imageUrl ? imageUrl.absoluteString : [NSNull null],
                       };

        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
    }
}

- (NSString*) reverseUrlScheme:(NSString*)scheme {
  NSArray* originalArray = [scheme componentsSeparatedByString:@"."];
  NSArray* reversedArray = [[originalArray reverseObjectEnumerator] allObjects];
  NSString* reversedString = [reversedArray componentsJoinedByString:@"."];
  return reversedString;
}

- (NSString*) getreversedClientId {
  NSArray* URLTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];

  if (URLTypes != nil) {
    for (NSDictionary* dict in URLTypes) {
      NSString *urlName = dict[@"CFBundleURLName"];
      if ([urlName isEqualToString:@"REVERSED_CLIENT_ID"]) {
        NSArray* URLSchemes = dict[@"CFBundleURLSchemes"];
        if (URLSchemes != nil) {
          return URLSchemes[0];
        }
      }
    }
  }
  return nil;
}

- (void) logout:(CDVInvokedUrlCommand*)command {
  [[GIDSignIn sharedInstance] signOut];
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"logged out"];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) disconnect:(CDVInvokedUrlCommand*)command {
    GIDSignIn *signIn = [GIDSignIn sharedInstance];
    [signIn disconnectWithCallback:^(NSError * _Nullable error) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"disconnected"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void) share_unused:(CDVInvokedUrlCommand*)command {
  // for a rainy day.. see for a (limited) example https://github.com/vleango/GooglePlus-PhoneGap-iOS/blob/master/src/ios/GPlus.m
}

- (NSString*)toJSONString:(NSDictionary*)dictionaryOrArray {
    NSError *error;
         NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionaryOrArray
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
         if (! jsonData) {
            NSLog(@"%s: error: %@", __func__, error.localizedDescription);
            return @"{}";
         } else {
            return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
         }
}

@end
