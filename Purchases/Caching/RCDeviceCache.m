//
//  RCDeviceCache.m
//  Purchases
//
//  Created by RevenueCat.
//  Copyright © 2019 Purchases. All rights reserved.
//

#import "RCDeviceCache.h"
#import "RCDeviceCache+Protected.h"


@interface RCDeviceCache ()

@property (nonatomic) NSUserDefaults *userDefaults;
@property (nonatomic, nonnull) RCInMemoryCachedObject<RCOfferings *> *offeringsCachedObject;
@property (nonatomic, nullable) NSDate *purchaserInfoCachesLastUpdated;

@end


#define RC_CACHE_KEY_PREFIX @"com.revenuecat.userdefaults"

NSString *RCLegacyGeneratedAppUserDefaultsKey = RC_CACHE_KEY_PREFIX @".appUserID";
NSString *RCAppUserDefaultsKey = RC_CACHE_KEY_PREFIX @".appUserID.new";
NSString *RCPurchaserInfoAppUserDefaultsKeyBase = RC_CACHE_KEY_PREFIX @".purchaserInfo.";
NSString *RCLegacySubscriberAttributesKeyBase = RC_CACHE_KEY_PREFIX @".subscriberAttributes.";
NSString *RCSubscriberAttributesKey = RC_CACHE_KEY_PREFIX @".subscriberAttributes";
#define CACHE_DURATION_IN_SECONDS 60 * 5


@implementation RCDeviceCache

- (instancetype)initWith:(NSUserDefaults *)userDefaults {
    return [self initWith:userDefaults offeringsCachedObject:nil];
}

- (instancetype)initWith:(NSUserDefaults *)userDefaults
   offeringsCachedObject:(RCInMemoryCachedObject<RCOfferings *> *)offeringsCachedObject {
    self = [super init];
    if (self) {
        if (userDefaults == nil) {
            userDefaults = [NSUserDefaults standardUserDefaults];
        }
        self.userDefaults = userDefaults;

        if (offeringsCachedObject == nil) {
            offeringsCachedObject =
                [[RCInMemoryCachedObject alloc] initWithCacheDurationInSeconds:CACHE_DURATION_IN_SECONDS];
        }
        self.offeringsCachedObject = offeringsCachedObject;

    }

    return self;
}

#pragma mark - appUserID

- (nullable NSString *)cachedLegacyAppUserID {
    return [self.userDefaults stringForKey:RCLegacyGeneratedAppUserDefaultsKey];
}

- (nullable NSString *)cachedAppUserID {
    return [self.userDefaults stringForKey:RCAppUserDefaultsKey];
}

- (void)cacheAppUserID:(NSString *)appUserID {
    [self.userDefaults setObject:appUserID forKey:RCAppUserDefaultsKey];
}

- (void)clearCachesForAppUserID:(NSString *)appUserID {
    [self.userDefaults removeObjectForKey:RCLegacyGeneratedAppUserDefaultsKey];
    [self.userDefaults removeObjectForKey:RCAppUserDefaultsKey];
    [self.userDefaults removeObjectForKey:[self purchaserInfoUserDefaultCacheKeyForAppUserID:appUserID]];
    [self clearPurchaserInfoCacheTimestamp];
    [self clearOfferingsCache];
    
    [self clearSubscriberAttributesIfSyncedForAppUserID:appUserID];
}

- (void)clearSubscriberAttributesIfSyncedForAppUserID:(NSString *)appUserID {
    if ([self numberOfUnsyncedAttributesForAppUserID:appUserID] == 0) {
        NSMutableDictionary *groupedSubscriberAttributes = self.groupedSubscriberAttributes.mutableCopy;
        [groupedSubscriberAttributes removeObjectForKey:appUserID];
        [self.userDefaults setObject:groupedSubscriberAttributes forKey:RCSubscriberAttributesKey];
    }
}

#pragma mark - purchaserInfo

- (nullable NSData *)cachedPurchaserInfoDataForAppUserID:(NSString *)appUserID {
    return [self.userDefaults dataForKey:[self purchaserInfoUserDefaultCacheKeyForAppUserID:appUserID]];
}

- (void)cachePurchaserInfo:(NSData *)data forAppUserID:(NSString *)appUserID {
    @synchronized (self) {
        [self.userDefaults setObject:data
                              forKey:[self purchaserInfoUserDefaultCacheKeyForAppUserID:appUserID]];
        [self setPurchaserInfoCacheTimestampToNow];
    }
}

- (BOOL)isPurchaserInfoCacheStale {
    NSTimeInterval timeSinceLastCheck = -[self.purchaserInfoCachesLastUpdated timeIntervalSinceNow];
    return !(self.purchaserInfoCachesLastUpdated != nil && timeSinceLastCheck < CACHE_DURATION_IN_SECONDS);
}

- (void)clearPurchaserInfoCacheTimestamp {
    self.purchaserInfoCachesLastUpdated = nil;
}

- (void)setPurchaserInfoCacheTimestampToNow {
    self.purchaserInfoCachesLastUpdated = [NSDate date];
}

- (NSString *)purchaserInfoUserDefaultCacheKeyForAppUserID:(NSString *)appUserID {
    return [RCPurchaserInfoAppUserDefaultsKeyBase stringByAppendingString:appUserID];
}

#pragma mark - offerings

- (nullable RCOfferings *)cachedOfferings {
    return self.offeringsCachedObject.cachedInstance;
}

- (void)cacheOfferings:(RCOfferings *)offerings {
    [self.offeringsCachedObject cacheInstance:offerings];
}

- (BOOL)isOfferingsCacheStale {
    return self.offeringsCachedObject.isCacheStale;
}

- (void)clearOfferingsCacheTimestamp {
    [self.offeringsCachedObject clearCacheTimestamp];
}

- (void)setOfferingsCacheTimestampToNow {
    [self.offeringsCachedObject updateCacheTimestampWithDate:[NSDate date]];
}

- (void)clearOfferingsCache {
    [self.offeringsCachedObject clearCache];
}

#pragma mark - subscriber attributes

- (void)storeSubscriberAttribute:(RCSubscriberAttribute *)attribute appUserID:(NSString *)appUserID {
    @synchronized (self) {
        NSMutableDictionary *groupedSubscriberAttributes = [self groupedSubscriberAttributes].mutableCopy;
        NSMutableDictionary *subscriberAttributesForAppUserID = ((NSDictionary *)groupedSubscriberAttributes[appUserID] ?: @{})
                                                                .mutableCopy;

        subscriberAttributesForAppUserID[attribute.key] = attribute.asDictionary;
        groupedSubscriberAttributes[appUserID] = subscriberAttributesForAppUserID;
        [self.userDefaults setObject:groupedSubscriberAttributes
                              forKey:RCSubscriberAttributesKey];
    }
}

- (void)storeSubscriberAttributes:(RCSubscriberAttributeDict)attributesByKey
                        appUserID:(NSString *)appUserID {
    if (attributesByKey.count == 0) {
        return;
    }

    @synchronized (self) {
        NSMutableDictionary *groupedSubscriberAttributes = [self groupedSubscriberAttributes].mutableCopy;
        NSMutableDictionary *subscriberAttributesForAppUserID = ((NSDictionary *)groupedSubscriberAttributes[appUserID] ?: @{})
                                                                 .mutableCopy;
    
        for (NSString *key in attributesByKey) {
            subscriberAttributesForAppUserID[key] = attributesByKey[key].asDictionary;
        }
        
        groupedSubscriberAttributes[appUserID] = subscriberAttributesForAppUserID;
        [self.userDefaults setObject:groupedSubscriberAttributes
                              forKey:RCSubscriberAttributesKey];
    }
}

- (NSDictionary *)subscriberAttributesForAppUserID:(NSString *)appUserID {
    return self.groupedSubscriberAttributes[appUserID] ?: @{};
}

- (NSDictionary *)groupedSubscriberAttributes {
    return [self.userDefaults dictionaryForKey:RCSubscriberAttributesKey] ?: @{};
}

- (nullable RCSubscriberAttribute *)subscriberAttributeWithKey:(NSString *)attributeKey
                                                     appUserID:(NSString *)appUserID {
    @synchronized (self) {
        RCSubscriberAttributeDict
            allSubscriberAttributesByKey = [self storedSubscriberAttributesForAppUserID:appUserID];
        return allSubscriberAttributesByKey[attributeKey];
    }
}

- (RCSubscriberAttributeDict)unsyncedAttributesByKeyForAppUserID:(NSString *)appUserID {
    @synchronized (self) {
        RCSubscriberAttributeDict
            allSubscriberAttributesByKey = [self storedSubscriberAttributesForAppUserID:appUserID];
        RCSubscriberAttributeMutableDict unsyncedAttributesByKey = [[NSMutableDictionary alloc] init];
        for (NSString *key in allSubscriberAttributesByKey) {
            RCSubscriberAttribute *attribute = allSubscriberAttributesByKey[key];
            if (!attribute.isSynced) {
                unsyncedAttributesByKey[attribute.key] = attribute;
            }
        }
        return unsyncedAttributesByKey;
    }
}

- (RCSubscriberAttributeDict)storedSubscriberAttributesForAppUserID:(NSString *)appUserID {
    NSDictionary <NSString *, NSObject *>
        *allAttributesObjectsByKey = [self subscriberAttributesForAppUserID:appUserID];
    RCSubscriberAttributeMutableDict allSubscriberAttributesByKey = [[NSMutableDictionary alloc] init];

    for (NSString *key in allAttributesObjectsByKey) {
        NSDictionary <NSString *, NSString *> *attributeAsDict =
            (NSDictionary <NSString *, NSString *> *) allAttributesObjectsByKey[key];
        allSubscriberAttributesByKey[key] = [[RCSubscriberAttribute alloc]
                                                                    initWithDictionary:attributeAsDict];
    }
    return allSubscriberAttributesByKey;
}

- (NSUInteger)numberOfUnsyncedAttributesForAppUserID:(NSString *)appUserID {
    return [self unsyncedAttributesByKeyForAppUserID:appUserID].count;
}

# pragma mark - subscriber attributes migration from per-user key to grouped key

- (void)migrateSubscriberAttributesIfNeededForAppUserID:(NSString *)appUserID {
    @synchronized (self) {
        NSDictionary *legacySubscriberAttributes = [self valueForLegacySubscriberAttributes:appUserID];
        if (legacySubscriberAttributes != nil) {
            [self migrateSubscriberAttributes:legacySubscriberAttributes withAppUserID:appUserID];
        }
    }
}

- (void)migrateSubscriberAttributes:(nonnull NSDictionary *)subscriberAttributes
                      withAppUserID:(NSString *)appUserID {
    NSMutableDictionary *allSubscriberAttributes = [self.userDefaults objectForKey:RCSubscriberAttributesKey]
                                                   ?: [[NSMutableDictionary alloc] init];
    NSMutableDictionary *currentAttributesForAppUserID = currentAttributesForAppUserID[appUserID]
                                                         ?: [[NSMutableDictionary alloc] init];
    NSMutableDictionary *mutableSubscriberAttributes = subscriberAttributes.mutableCopy;
    [mutableSubscriberAttributes addEntriesFromDictionary:currentAttributesForAppUserID];

    allSubscriberAttributes[appUserID] = mutableSubscriberAttributes;
    [self.userDefaults setObject:allSubscriberAttributes forKey:RCSubscriberAttributesKey];
}

- (nullable NSDictionary *)valueForLegacySubscriberAttributes:(NSString *)appUserID {
    return [self.userDefaults dictionaryForKey:[self legacySubscriberAttributesCacheKeyForAppUserID:appUserID]];
}

- (NSString *)legacySubscriberAttributesCacheKeyForAppUserID:(NSString *)appUserID {
    NSString *attributeKey = [NSString stringWithFormat:@"%@", appUserID];
    return [RCLegacySubscriberAttributesKeyBase stringByAppendingString:attributeKey];
}

- (NSDictionary<NSString *, RCSubscriberAttributeDict> *)unsyncedAttributesByKeyForAllUsers {
    return [self groupedSubscriberAttributes];
}

- (void)deleteAttributesIfSyncedForAppUserID:(NSString *)appUserID {
    @synchronized (self) {
        if ([self numberOfUnsyncedAttributesForAppUserID:appUserID] != 0) {
            return;
        }
        
        NSMutableDictionary <NSString *, RCSubscriberAttributeDict>
            *groupedAttributes = [self groupedSubscriberAttributes].mutableCopy;
        [groupedAttributes removeObjectForKey:appUserID];
        [self.userDefaults setObject:groupedAttributes forKey:RCSubscriberAttributesKey];
    }
}

@end

