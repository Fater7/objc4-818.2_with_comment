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

`runtime`启动的入口在`_objc_init`函数中。在这里，使用`_dyld_objc_notify_register`向`dyld`注册了三个回调方法`map_images`，`load_images`，`unmap_image`：

```cpp
// objc-os.mm
void _objc_init(void)
{
    // ...
    _dyld_objc_notify_register(&map_images, load_images, unmap_image);
    // ...
}
```

### map_images

`map_images`在`dyld`将所有镜像文件映射到内存后执行。包含三个参数：

- `mhCount`：镜像数量。
- `mhPaths`：各镜像在磁盘中的路径。
- `mhdrs`：`mach_header`结构数组，各镜像mach-o头信息。

`map_images`加锁后调用`map_images_nolock`。`map_images_nolock`中调用`addHeader`方法，逐一生成包含每个镜像信息的`header_info`结构。所有`header_info`还会存入全局链表，供之后的`load_images`方法使用。

有了`header_info`之后，通过`_read_images`方法读取镜像中的所有`SEL`、`Class`、`Protocol`信息，生成对应的结构并存入全局表。处理类信息的方法为`readClass`，在这里，会调用上一节中的`popFutureNamedClass`方法尝试获取该类名对应的`Future Class`，如果存在，则会使用`Future Class`提前分配好的内存存储该类信息。

### load_images

`load_images`方法的执行次数对应于镜像的数量，在每一个镜像初始化的时候都会执行。

`load_images`首先会通过`loadAllCategories`方法遍历`map_images`中记录的`header_info`全局链表，处理所有镜像中的分类信息，将分类的内容添加至本类。该逻辑虽然由`load_images`发起，但在全局只会执行一次。

之后，`load_images`会通过`prepare_load_methods`方法将所有本类与分类的`+load`方法的函数指针记录在全局表中。本类与分类的方法记录在了两个不同的表中，并且父类的`+load`方法信息会记录在子类之前。

```cpp
// objc-runtime-new.mm
// 递归将本类load方法存表
static void schedule_class_load(Class cls)
{
    if (!cls) return;
    ASSERT(cls->isRealized());  // _read_images should realize

    if (cls->data()->flags & RW_LOADED) return;

    // 父类先于子类存储+load方法
    schedule_class_load(cls->getSuperclass());

    add_class_to_loadable_list(cls);
    cls->setInfo(RW_LOADED); 
}
```

在`+load`方法记录完成后，`load_images`通过`call_load_methods`方法依次执行所有`+load`方法函数指针，保证父类先于子类执行，本类先于分类执行。

### unmap_image

将`map_images`时加载到内存中的信息全部移除。