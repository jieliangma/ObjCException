//
//  try_block_count.h
//  ObjCException
//
//  Created by JieLiang Ma on 2023/7/26.
//

#ifndef try_block_count_h
#define try_block_count_h

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT int get_try_block_count(void);
FOUNDATION_EXPORT int increase_try_block_count(void);
FOUNDATION_EXPORT int decrease_try_block_count(void);

#endif /* try_block_count_h */
