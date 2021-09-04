# iOS类加载

## Future Class

```cpp
// class is unrealized future class - must never be set by compiler
#define RO_FUTURE             (1<<30)
// class is unresolved future class
#define RW_FUTURE             (1<<30)
```

`RO_FUTURE` 与`RW_FUTURE`是`class_ro_t`与`class_rw_t`的相同标记位，用于标记该类是一个**提前分配好内存空间，但并未包含类信息的`Future Class`结构**。

`Future Class`在`addFutureNamedClass`中根据类名生成，并存至一个全局的`NXMapTable`哈希表结构中：

```cpp
// objc-runtime-new.mm
// objc_getFutureClass -> _objc_allocateFutureClass -> addFutureNamedClass
static void addFutureNamedClass(const char *name, Class cls)
{
    void *old;

    runtimeLock.assertLocked();

    if (PrintFuture) {
        _objc_inform("FUTURE: reserving %p for %s", (void*)cls, name);
    }

    // 分配内存空间
    class_rw_t *rw = objc::zalloc<class_rw_t>();
    class_ro_t *ro = (class_ro_t *)calloc(sizeof(class_ro_t), 1);
    ro->name.store(strdupIfMutable(name), std::memory_order_relaxed);
    rw->set_ro(ro);
    cls->setData(rw);
    // 置RO_FUTURE
    cls->data()->flags = RO_FUTURE;

    // 存表
    old = NXMapKeyCopyingInsert(futureNamedClasses(), name, cls);
    ASSERT(!old);
}
```

`addFutureNamedClass`追溯本源是在`objc_getFutureClass`中调用，源码中并没有找到`objc_getFutureClass`的调用时机，这一部分隐藏在了未开源的逻辑中。生产`Future Class`的时机未开源，但消费`Future Class`的时机却是公开的，从全局哈希表取`Future Class`的入口在`popFutureNamedClass`中：

```cpp
// objc-runtime-new.mm
static Class popFutureNamedClass(const char *name)
{
    runtimeLock.assertLocked();

    Class cls = nil;

    if (future_named_class_map) {
        cls = (Class)NXMapKeyFreeingRemove(future_named_class_map, name);
        if (cls && NXCountMapTable(future_named_class_map) == 0) {
            NXFreeMapTable(future_named_class_map);
            future_named_class_map = nil;
        }
    }

    return cls;
}
```

至于什么时候消费`Future Class`，这一部分稍后再说。

## 加载主流程

`runtime`启动的入口在`_objc_init`函数中。在这里，使用`_dyld_objc_notify_register`向`dyld`注册了三个回调方法：

```cpp
// objc-os.mm
void _objc_init(void)
{
    // ...
    _dyld_objc_notify_register(&map_images, load_images, unmap_image);
    // ...
}
```

抛去复杂的逻辑，这三个回调主要干了下述事情：

- map_images

在dyld映射镜像信息后触发，触发一次。加载所有的镜像头，读取镜像中的类、协议、方法等信息并记录到全局表中。

- load_images

在dyld初始化镜像信息后触发，触发多次。遍历记录所有类与分类的`+load`方法，并逐一执行。

- unmap_image

在dyld卸载镜像时触发。移除map_images时记录在全局表中的信息。

### map_images

map_images加锁后调用map_images_nolock。map_images_nolock中对