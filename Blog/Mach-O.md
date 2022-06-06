# Mach-O

# 分析工具

- 命令工具：`lipo`、`ar`、`nm`、`otool`。
- 软件工具：`MachOView`、`Hopper Disassembler`。

# 文件组成

组成结构定义于系统的[loader.h](https://opensource.apple.com/source/xnu/xnu-7195.141.2/EXTERNAL_HEADERS/mach-o/loader.h.auto.html)文件中。

## Mach Header

```c
// 32位定义
struct mach_header {
	uint32_t	magic;		/* mach magic number identifier */
	cpu_type_t	cputype;	/* cpu specifier */
	cpu_subtype_t	cpusubtype;	/* machine specifier */
	uint32_t	filetype;	/* type of file */
	uint32_t	ncmds;		/* number of load commands */
	uint32_t	sizeofcmds;	/* the size of all the load commands */
	uint32_t	flags;		/* flags */
};

/* Constant for the magic field of the mach_header (32-bit architectures) */
#define	MH_MAGIC	0xfeedface	/* the mach magic number */
#define MH_CIGAM	0xcefaedfe	/* NXSwapInt(MH_MAGIC) */

// 64位定义，8个4字节值，固定32字节
struct mach_header_64 {
	uint32_t	magic;		/* mach magic number identifier */
	cpu_type_t	cputype;	/* cpu specifier */
	cpu_subtype_t	cpusubtype;	/* machine specifier */
	uint32_t	filetype;	/* type of file */
	uint32_t	ncmds;		/* number of load commands */
	uint32_t	sizeofcmds;	/* the size of all the load commands */
	uint32_t	flags;		/* flags */
	uint32_t	reserved;	/* reserved */
};

/* Constant for the magic field of the mach_header_64 (64-bit architectures) */
#define MH_MAGIC_64 0xfeedfacf /* the 64-bit mach magic number */
#define MH_CIGAM_64 0xcffaedfe /* NXSwapInt(MH_MAGIC_64) */
```

- **magic**：区分32位/64位设备。
- **cputype**：cpu架构类型，以`CPU_TYPE_`为前缀定义宏值。
- **cpusubtype**：cpu子类型，以`CPU_SUBTYPE_`为前缀定义宏值。

- **filetype**：mach-o文件类型，以`MH_`为前缀定义宏值。
- **ncmds**：加载命令数量。
- **sizeofcmds**：加载命令占总字节数。
- **flags**：其他标记，以`MH_`为前缀定义宏值。
- **reserved**：保留位。

## Load Commands

指导如何设置加载对应的二进制段。

有不同种类型的加载命令，对应着不同的结构。但是所有加载命令的前8个字节都表示命令类型与命令大小：

```c
struct load_command {
	uint32_t cmd;		/* type of load command */
	uint32_t cmdsize;	/* total size of command in bytes */
};
```

`cmd`表示命令类型，以`LC_`为前缀定义宏值。

`cmdsize`表示命令所占字节数。在64位架构下，`cmdsize`必须为8字节的整数倍。32位下需为4的整数倍。

### LC_SEGMENT_64

`segment_command`用于描述系统如何加载该Mach-O文件的各Segment数据。64位架构下，命令类型为`LC_SEGMENT_64`：

```c
// 32位
#define	LC_SEGMENT	0x1	/* segment of this file to be mapped */

struct segment_command { /* for 32-bit architectures */
	uint32_t	cmd;		/* LC_SEGMENT */
	uint32_t	cmdsize;	/* includes sizeof section structs */
	char		segname[16];	/* segment name */
	uint32_t	vmaddr;		/* memory address of this segment */
	uint32_t	vmsize;		/* memory size of this segment */
	uint32_t	fileoff;	/* file offset of this segment */
	uint32_t	filesize;	/* amount to map from the file */
	vm_prot_t	maxprot;	/* maximum VM protection */
	vm_prot_t	initprot;	/* initial VM protection */
	uint32_t	nsects;		/* number of sections in segment */
	uint32_t	flags;		/* flags */
};

// 64位
#define	LC_SEGMENT_64	0x19	/* 64-bit segment of this file to be mapped */

struct segment_command_64 { /* for 64-bit architectures */
	uint32_t	cmd;		/* LC_SEGMENT_64 */
	uint32_t	cmdsize;	/* includes sizeof section_64 structs */
	char		segname[16];	/* segment name */
	uint64_t	vmaddr;		/* memory address of this segment */
	uint64_t	vmsize;		/* memory size of this segment */
	uint64_t	fileoff;	/* file offset of this segment */
	uint64_t	filesize;	/* amount to map from the file */
	vm_prot_t	maxprot;	/* maximum VM protection */
	vm_prot_t	initprot;	/* initial VM protection */
	uint32_t	nsects;		/* number of sections in segment */
	uint32_t	flags;		/* flags */
};
```

- **segname**：当前结构所描述的segment名称，以SEG_为前缀定义宏值：

```c
#define	SEG_PAGEZERO	"__PAGEZERO"
#define	SEG_TEXT		"__TEXT"
#define	SEG_DATA		"__DATA"
// ...
```

- **vmaddr**：该segment数据在进程地址空间中映射时的起始地址。
- **vmsize**：该segment在进程空间所占字节数。
- **fileoff**：segment在文件中的起始地址偏移量。
- **filesize**：segment在文件中所占字节数。
- **maxprot**，**initprot**：segment的起始与最大权限，以`VM_PORT_`为前缀定义的无重复位宏值：

```c
typedef int             vm_prot_t;

#define VM_PROT_NONE    ((vm_prot_t) 0x00)
#define VM_PROT_READ    ((vm_prot_t) 0x01)      /* read permission */
#define VM_PROT_WRITE   ((vm_prot_t) 0x02)      /* write permission */
#define VM_PROT_EXECUTE ((vm_prot_t) 0x04)      /* execute permission */

#define VM_PROT_DEFAULT (VM_PROT_READ|VM_PROT_WRITE)
```

- **nsects**：该segment所包含的section数量。
- **flags**：其他标记。

对于每一个section，都在该`segment_command`之后，紧跟着使用`section`结构描述：

```c
struct section { /* for 32-bit architectures */
	char		sectname[16];	/* name of this section */
	char		segname[16];	/* segment this section goes in */
	uint32_t	addr;		/* memory address of this section */
	uint32_t	size;		/* size in bytes of this section */
	uint32_t	offset;		/* file offset of this section */
	uint32_t	align;		/* section alignment (power of 2) */
	uint32_t	reloff;		/* file offset of relocation entries */
	uint32_t	nreloc;		/* number of relocation entries */
	uint32_t	flags;		/* flags (section type and attributes)*/
	uint32_t	reserved1;	/* reserved (for offset or index) */
	uint32_t	reserved2;	/* reserved (for count or sizeof) */
};

struct section_64 { /* for 64-bit architectures */
	char		sectname[16];	/* name of this section */
	char		segname[16];	/* segment this section goes in */
	uint64_t	addr;		/* memory address of this section */
	uint64_t	size;		/* size in bytes of this section */
	uint32_t	offset;		/* file offset of this section */
	uint32_t	align;		/* section alignment (power of 2) */
	uint32_t	reloff;		/* file offset of relocation entries */
	uint32_t	nreloc;		/* number of relocation entries */
	uint32_t	flags;		/* flags (section type and attributes)*/
	uint32_t	reserved1;	/* reserved (for offset or index) */
	uint32_t	reserved2;	/* reserved (for count or sizeof) */
	uint32_t	reserved3;	/* reserved */
};
```

- **sectname**：section名称，以`SECT_`为前缀定义宏值。

```c
#define	SECT_TEXT	"__text"
#define	SECT_DATA	"__data"
#define	SECT_BSS	"__bss"
// ...
```

- **segname**：对应segment的名称。
- **addr**：该section映射到进程地址空间后的起始地址。
- **size**：section所占字节数。
- **offset**：section在文件中的起始地址偏移量。
- **align**：section在虚拟内存中的起始地址必须满足的对齐位。
- **reloff**：该section中重定向符号信息在文件中的偏移位置。
- **nreloc**：该section中需要重定向的符号数量。

- **Flags**：其他标识，以`S_`为前缀定义宏值。

### LC_DYLD_INFO

`dyld_info_commnd`用来描述`OS X 10.6`之后dyld加载镜像所需要的一些信息。命令类型为`LC_DYLD_INFO`或`LC_DYLD_INFO_ONLY`：

```c
struct dyld_info_command {
   	uint32_t   cmd;		/* LC_DYLD_INFO or LC_DYLD_INFO_ONLY */
   	uint32_t   cmdsize;		/* sizeof(struct dyld_info_command) */
    uint32_t   rebase_off;	/* file offset to rebase info  */
    uint32_t   rebase_size;	/* size of rebase info   */
    
    uint32_t   bind_off;	/* file offset to binding info   */
    uint32_t   bind_size;	/* size of binding info  */

    uint32_t   weak_bind_off;	/* file offset to weak binding info   */
    uint32_t   weak_bind_size;  /* size of weak binding info  */
    
    uint32_t   lazy_bind_off;	/* file offset to lazy binding info */
    uint32_t   lazy_bind_size;  
    
    uint32_t   export_off;	/* file offset to lazy binding info */
    uint32_t   export_size;	/* size of lazy binding infs */
};
```

### LC_SYMTAB

`symtab_command`用来描述Mach-O文件中符号表的信息，命令类型为`LC_SYMTAB`：

```c
struct symtab_command {
	uint32_t	cmd;		/* LC_SYMTAB */
	uint32_t	cmdsize;	/* sizeof(struct symtab_command) */
	uint32_t	symoff;		/* symbol table offset */
	uint32_t	nsyms;		/* number of symbol table entries */
	uint32_t	stroff;		/* string table offset */
	uint32_t	strsize;	/* string table size in bytes */
};
```

### LC_DYSYMTAB

`dysymtab_command`用来描述动态链接中所需的间接符号表的信息，命令类型为`LC_DYSYMTAB`：

### LC_LOAD_DYLINKER

对于一个需要用到动态链接器的可执行文件，使用`dylinker_command`来描述动态链接器在磁盘上的路径位置。

可执行文件中该命令的类型为`LC_LOAD_DYLINKER`，而对于一个动态链接器，其本身所持有的该命令用于标识自身，命令类型为`LC_ID_DYLINKER`。

该命令也可用于将动态链接器描述为环境变量，命令类型为`LC_DYLD_ENVIRONMENT`。

```c
union lc_str {
	uint32_t	offset;	/* offset to the string */
#ifndef __LP64__
	char		*ptr;	/* pointer to the string */
#endif 
};

struct dylinker_command {
	uint32_t cmd;		/* LC_ID_DYLINKER, LC_LOAD_DYLINKER or LC_DYLD_ENVIRONMENT */
	uint32_t cmdsize;	/* includes pathname string */
	union lc_str name;	/* dynamic linker's path name */
};
```

### LC_UUID

用于记录Mach-O文件的唯一标识，命令类型为`LC_UUID`：

```c
struct uuid_command {
    uint32_t	cmd;		/* LC_UUID */
    uint32_t	cmdsize;	/* sizeof(struct uuid_command) */
    uint8_t	uuid[16];		/* the 128-bit uuid */
};
```

### LC_BUILD_VERSION

`build_version_command`用于描述二进制的目标运行环境，命令类型为`LC_BUILD_VERSION`：

```c
struct build_version_command {
    uint32_t	cmd;		/* LC_BUILD_VERSION */
    uint32_t	cmdsize;	/* 命令大小包含tool */
    uint32_t	platform;	/* platform */
    uint32_t	minos;		/* X.Y.Z is encoded in nibbles xxxx.yy.zz */
    uint32_t	sdk;		/* X.Y.Z is encoded in nibbles xxxx.yy.zz */
    uint32_t	ntools;		/* number of tool entries following this */
};

struct build_tool_version {
    uint32_t	tool;		/* enum for the tool */
    uint32_t	version;	/* version number of the tool */
};
```

- **platform**：硬件平台，以`PLATFORM_`为前缀定义宏值。

- **ntools**：构建工具数量。对于每一个tool，会由一个`build_tool_version`结构紧跟定义在其后。
- **tool**：构建工具类型，以`TOOL_`为前缀定义宏值。

### LC_MAIN

用于可执行程序标识main函数位置，命令类型为`LC_MAIN`：

```c
struct entry_point_command {
    uint32_t  cmd;	/* LC_MAIN only used in MH_EXECUTE filetypes */
    uint32_t  cmdsize;	/* 24 */
    uint64_t  entryoff;	/* file (__TEXT) offset of main() */
    uint64_t  stacksize;/* if not zero, initial stack size */
};
```

### LC_LOAD_DYLIB

对于`header`中`filetype`为`MH_DYLIB`的动态库文件，命令类型为`LC_ID_DYLIB`，用于描述该动态库信息。

对于需要引用动态库的Mach-O文件，命令类型为`LC_LOAD_DYLIB`、`LC_LOAD_WEAK_DYLIB`或`LC_REEXPORT_DYLIB`，用于描述引用的动态库信息：

```c
struct dylib {
    union lc_str  name;			/* library's path name */
    uint32_t timestamp;			/* library's build time stamp */
    uint32_t current_version;		/* library's current version number */
    uint32_t compatibility_version;	/* library's compatibility vers number*/
};

struct dylib_command {
	uint32_t	cmd;		
	uint32_t	cmdsize;	/* includes pathname string */
	struct dylib	dylib;		/* the library identification */
};
```

## Data

### __TEXT

### __DATA

### Relocations

重定向表记录了每个section中需要在链接后重定向的符号。重定向符号表在文件中的偏移位置与重定向符号的数量，都在前面Load Commands中该section信息里记录。

每一个重定向符号使用`relocation_info`结构定义：

```c
struct relocation_info {
   	int32_t	r_address;	/* offset in the section to what is being
				   relocated */
    
    // 位域结构记录
   	uint32_t     r_symbolnum:24,	/* symbol index if r_extern == 1 or section
				   ordinal if r_extern == 0 */
		r_pcrel:1, 	/* was relocated pc relative already */
		r_length:2,	/* 0=byte, 1=word, 2=long, 3=quad */
		r_extern:1,	/* does not include value of sym referenced */
		r_type:4;	/* if not 0, machine specific relocation type */
};
```

- `r_address`：该符号在section中被使用时的偏移位置？。

- `r_symbolnum`：24bit。当`r_extern`为1时，代表该符号在符号表中的次序。为0时，代表section次序。
- `r_pcrel`：？
- `r_length`：2bit。该符号长度。
- `r_extern`：？
- `r_type`：4bit。符号类型？











