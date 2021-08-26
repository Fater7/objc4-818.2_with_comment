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
    // Property
    UInt32 pCount;
    objc_property_t *properties = class_copyPropertyList(objc_getClass("Person"), &pCount);
    for (UInt32 i = 0; i < pCount; i++) {
        objc_property_t p = properties[i];
        NSLog(@"%s_%s", property_getName(p), property_getAttributes(p));
    }

    // Method
    UInt32 mCount;
    Method *methods = class_copyMethodList(objc_getClass("Person"), &mCount);
    for (UInt32 i = 0; i < mCount; i++) {
        Method m = methods[i];
        NSLog(@"%@_%s", NSStringFromSelector(method_getName(m)), method_getTypeEncoding(m));
    }

    return 0;
}
