//
//  Person+Student.m
//  ObjcExample
//
//  Created by Fater on 2021/9/10.
//

#import "Person+Student.h"

@implementation Person (Student)

- (NSString *)school {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setSchool:(NSString *)school {
    objc_setAssociatedObject(self, @selector(school), school, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@end
