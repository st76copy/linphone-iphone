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
        retImage = [[[UIImage alloc] initWithData:(NSData *)imgData] autorelease];
        CFRelease(imgData);    
    }
    return retImage;
}

- (ABRecordRef)getContact:(NSString*)address {
    @synchronized (mAddressBookMap){
        return (ABRecordRef)[mAddressBookMap objectForKey:address];   
    } 
}

+ (NSString*)appendCountryCodeIfPossible:(NSString*)number {
    if (![number hasPrefix:@"+"] && ![number hasPrefix:@"00"]) {
        NSString* lCountryCode = [[LinphoneManager instance].settingsStore objectForKey:@"countrycode_preference"];
        if (lCountryCode && [lCountryCode length]>0) {
            //append country code
            return [lCountryCode stringByAppendingString:number];
        }
    }
    return number;
}

+ (NSString*)normalizeSipURI:(NSString*)address {
    return address;
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

void sync_address_book (ABAddressBookRef addressBook, CFDictionaryRef info, void *context) {
    NSMutableDictionary* lAddressBookMap = (NSMutableDictionary*)context;
    @synchronized (lAddressBookMap) {
        [lAddressBookMap removeAllObjects];
        
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
                        [lAddressBookMap setObject:lPerson forKey:lNormalizedKey];
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
                        if(CFDictionaryContainsKey(lDict, kABPersonInstantMessageServiceKey)) {
                            if(CFStringCompare((CFStringRef)CONTACT_SIP_FIELD, CFDictionaryGetValue(lDict, kABPersonInstantMessageServiceKey), kCFCompareCaseInsensitive) == 0) {
                                CFStringRef lValue = CFDictionaryGetValue(lDict, kABPersonInstantMessageUsernameKey);
                                NSString* lNormalizedKey = [FastAddressBook normalizeSipURI:(NSString*)lValue];
                                [lAddressBookMap setObject:lPerson forKey:lNormalizedKey];
                            }
                        }
                        CFRelease(lDict);
                    }
                    CFRelease(lMap);   
                }
            }
        }
        CFRelease(lContacts);
    }
}

- (FastAddressBook*)init {
    if ((self = [super init]) != nil) {
        mAddressBookMap  = [[NSMutableDictionary alloc] init];
        addressBook = ABAddressBookCreate();
        ABAddressBookRegisterExternalChangeCallback (addressBook, sync_address_book, mAddressBookMap);
        sync_address_book(addressBook,nil,mAddressBookMap);
    }
    return self;
}

- (void)dealloc {
    ABAddressBookUnregisterExternalChangeCallback(addressBook, sync_address_book, mAddressBookMap);
    CFRelease(addressBook);
    [super dealloc];
}

@end