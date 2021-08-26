//
//  main.m
//  ObjcExample
//
//  Created by Bill Li on 2021/8/16.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "Person.h"

int main(int argc, const char * argv[]) {
    unsigned int pCount;
    objc_property_t *properties = class_copyPropertyList(objc_getClass("Person"), &pCount);
    for (UInt32 i = 0; i < pCount; i++) {
        objc_property_t p = properties[i];
        NSLog(@"%@, %@", [NSString stringWithCString:property_getName(p) encoding:NSUTF8StringEncoding], [NSString stringWithCString:property_getAttributes(p) encoding:NSUTF8StringEncoding]);
    }
    return 0;
}
