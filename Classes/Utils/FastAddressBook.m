/* FastAddressBook.h
 *
 * Copyright (C) 2011  Belledonne Comunications, Grenoble, France
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or   
 *  (at your option) any later version.                                 
 *                                                                      
 *  This program is distributed in the hope that it will be useful,     
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of      
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the       
 *  GNU General Public License for more details.                
 *                                                                      
 *  You should have received a copy of the GNU General Public License   
 *  along with this program; if not, write to the Free Software         
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */   

#import "FastAddressBook.h"
#import "LinphoneManager.h"

@implementation FastAddressBook

+ (NSString*)getContactDisplayName:(ABRecordRef)contact {
    NSString *retString = nil;
    if (contact) {
        CFStringRef lDisplayName = ABRecordCopyCompositeName(contact);
        if(lDisplayName != NULL) {
            retString = [NSString stringWithString:(NSString*)lDisplayName];
            CFRelease(lDisplayName);
        }
    }
    return retString;
}

+ (UIImage*)getContactImage:(ABRecordRef)contact thumbnail:(BOOL)thumbnail {
    UIImage* retImage = nil;
    if (contact && ABPersonHasImageData(contact)) {
        CFDataRef imgData = ABPersonCopyImageDataWithFormat(contact, thumbnail? 
                                                            kABPersonImageFormatThumbnail: kABPersonImageFormatOriginalSize);
        retImage = [UIImage imageWithData:(NSData *)imgData];
        CFRelease(imgData);    
    }
    return retImage;
}

- (ABRecordRef)getContact:(NSString*)address {
    @synchronized (addressBookMap){
        return (ABRecordRef)[addressBookMap objectForKey:address];   
    } 
}

+ (BOOL)isSipURI:(NSString*)address {
    return [address hasPrefix:@"sip:"];
}

+ (NSString*)appendCountryCodeIfPossible:(NSString*)number {
    if (![number hasPrefix:@"+"] && ![number hasPrefix:@"00"]) {
        NSString* lCountryCode = [[LinphoneManager instance] lpConfigStringForKey:@"countrycode_preference"];
        if (lCountryCode && [lCountryCode length]>0) {
            //append country code
            return [lCountryCode stringByAppendingString:number];
        }
    }
    return number;
}

+ (NSString*)normalizeSipURI:(NSString*)address {
    NSString* ret = address;
    if([address rangeOfString:@"@"].location != NSNotFound) {
        if([address rangeOfString:@"sip:" options:NSCaseInsensitiveSearch].location == 0) {
            // have to be sure that start with sip: in lower case
            ret = [ret substringFromIndex:4];
        }
        ret = [@"sip:" stringByAppendingString:ret];
        if([ret hasSuffix:@":5060"]) {
            ret = [ret substringToIndex:[ret length] - 5];
        }
    }
    return ret;
}

+ (NSString*)normalizePhoneNumber:(NSString*)address {
    NSMutableString* lNormalizedAddress = [NSMutableString stringWithString:address];
    [lNormalizedAddress replaceOccurrencesOfString:@" " 
                                        withString:@"" 
                                           options:0
                                             range:NSMakeRange(0, [lNormalizedAddress length])];
    [lNormalizedAddress replaceOccurrencesOfString:@"(" 
                                        withString:@"" 
                                           options:0
                                             range:NSMakeRange(0, [lNormalizedAddress length])];
    [lNormalizedAddress replaceOccurrencesOfString:@")" 
                                        withString:@"" 
                                           options:0
                                             range:NSMakeRange(0, [lNormalizedAddress length])];
    [lNormalizedAddress replaceOccurrencesOfString:@"-" 
                                        withString:@"" 
                                           options:0
                                             range:NSMakeRange(0, [lNormalizedAddress length])];
    return [FastAddressBook appendCountryCodeIfPossible:lNormalizedAddress];
}

- (FastAddressBook*)init {
    if ((self = [super init]) != nil) {
        addressBookMap  = [[NSMutableDictionary alloc] init];
        addressBook = ABAddressBookCreate();
        ABAddressBookRegisterExternalChangeCallback (addressBook, sync_address_book, self);
        [self loadData];
    }
    return self;
}

- (void)loadData {
    ABAddressBookRevert(addressBook);
    @synchronized (addressBookMap) {
        [addressBookMap removeAllObjects];
        
        NSArray *lContacts = (NSArray *)ABAddressBookCopyArrayOfAllPeople(addressBook);
        for (id lPerson in lContacts) {
            // Phone
            {
                ABMultiValueRef lMap = ABRecordCopyValue((ABRecordRef)lPerson, kABPersonPhoneProperty);
                if(lMap) {
                    for (int i=0; i<ABMultiValueGetCount(lMap); i++) {
                        CFStringRef lValue = ABMultiValueCopyValueAtIndex(lMap, i);
                        CFStringRef lLabel = ABMultiValueCopyLabelAtIndex(lMap, i);
                        CFStringRef lLocalizedLabel = ABAddressBookCopyLocalizedLabel(lLabel);
                        NSString* lNormalizedKey = [FastAddressBook normalizePhoneNumber:(NSString*)lValue];
                        [addressBookMap setObject:lPerson forKey:lNormalizedKey];
                        CFRelease(lValue);
                        if (lLabel) CFRelease(lLabel);
                        if (lLocalizedLabel) CFRelease(lLocalizedLabel);
                    }
                    CFRelease(lMap);
                }
            }
            
            // SIP
            {
                ABMultiValueRef lMap = ABRecordCopyValue((ABRecordRef)lPerson, kABPersonInstantMessageProperty);
                if(lMap) {
                    for(int i = 0; i < ABMultiValueGetCount(lMap); ++i) {
                        CFDictionaryRef lDict = ABMultiValueCopyValueAtIndex(lMap, i);
                        BOOL add = false;
                        if(CFDictionaryContainsKey(lDict, kABPersonInstantMessageServiceKey)) {
                            if(CFStringCompare((CFStringRef)kContactSipField, CFDictionaryGetValue(lDict, kABPersonInstantMessageServiceKey), kCFCompareCaseInsensitive) == 0) {
                                add = true;
                            }
                        } else {
                            add = true;
                        }
                        if(add) {
                            CFStringRef lValue = CFDictionaryGetValue(lDict, kABPersonInstantMessageUsernameKey);
                            NSString* lNormalizedKey = [FastAddressBook normalizeSipURI:(NSString*)lValue];
                            [addressBookMap setObject:lPerson forKey:lNormalizedKey];
                        }
                        CFRelease(lDict);
                    }
                    CFRelease(lMap);   
                }
            }
        }
        CFRelease(lContacts);
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kLinphoneAddressBookUpdate object:self];
}

void sync_address_book (ABAddressBookRef addressBook, CFDictionaryRef info, void *context) {
    FastAddressBook* fastAddressBook = (FastAddressBook*)context;
    [fastAddressBook loadData];
}

- (void)dealloc {
    ABAddressBookUnregisterExternalChangeCallback(addressBook, sync_address_book, self);
    CFRelease(addressBook);
    [addressBookMap release];
    [super dealloc];
}

@end
