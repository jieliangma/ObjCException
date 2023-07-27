//
//  OCECppCrash.mm
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/2/27.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

#import "OCECppCrash.h"
#import <ObjCException/ObjCException.h>
#include <string>

class object_in_stack {
public:
    object_in_stack(const char *name) {
        _name = name;
        NSLog(@"alloc %s", name);
    }
    
    ~object_in_stack() {
        NSLog(@"dealloc %s", _name.c_str());
    }
private:
    std::string _name;
};


void cpp_crash() {
    object_in_stack object_level_one("level_one");
    oce_try_catch(^{
        object_in_stack object_level_two("level_two");
        ((char *)0)[0] = 0;
    }, ^(NSException * _Nonnull exception) {
        NSLog(@"saved my life. (%@)", exception.name);
    });
}

void deep() {
    ((char *)0)[0] = 0;
}

void cpp_crash_deeper() {
    object_in_stack object_level_one("level_one");
    oce_try_catch(^{
        object_in_stack object_level_two("level_two");
        deep();
    }, ^(NSException * _Nonnull exception) {
        NSLog(@"saved my life. (%@)", exception.name);
    });
}
