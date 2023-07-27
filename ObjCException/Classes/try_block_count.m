//
//  try_block_count.c
//  ObjCException
//
//  Created by JieLiang Ma on 2023/7/26.
//

#include "try_block_count.h"

#include <pthread.h>
#include <stdlib.h>

static pthread_key_t try_block_count_key;
static pthread_once_t try_block_count_key_once = PTHREAD_ONCE_INIT;

static void try_block_count_destroy(void *buf) {
    if (buf)
        free(buf);

    pthread_setspecific(try_block_count_key, NULL);
}

static void try_block_count_key_alloc(void) {
    pthread_key_create(&try_block_count_key, try_block_count_destroy);
}

static int *try_block_count_pointer(void) {
    int *count;

    pthread_once(&try_block_count_key_once, try_block_count_key_alloc);

    count = pthread_getspecific(try_block_count_key);

    if (!count) {
        count = malloc(sizeof(int));
        pthread_setspecific(try_block_count_key, count);
    }
    return count;
}

int get_try_block_count(void) {
    return *try_block_count_pointer();
}

int increase_try_block_count(void) {
    int *pointer = try_block_count_pointer();
    
    *pointer += 1;
    return 0;
}

int decrease_try_block_count(void) {
    int *pointer = try_block_count_pointer();
    
    if (*pointer <= 0) {
        return -1;
    }
    
    *pointer -= 1;
    return 0;
}
