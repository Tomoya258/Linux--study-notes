# 常用文件操作命令(touch/cat/more/cp/mv/rm/which/find)

## 学习日期
2026-07-27

## 目标
掌握文件查看、复制移动删除、命令查找等基础操作命令

## 命令记录

```bash
# touch:创建空文件 / 更新文件时间戳
touch newfile.txt              # 文件不存在则创建空文件
touch existingfile.txt         # 文件存在则更新mtime(修改时间)为当前时间
touch -t 202401010000 old.log  # 手动指定时间戳
touch -d "3 days ago" file.txt # 设成相对时间

# cat:查看文件内容(适合小文件,一次性输出全部)
cat filename

# more:分页查看文件内容(适合大文件,空格翻页,q退出)
more filename

# cp:复制文件/目录
cp source.txt dest.txt         # 复制文件
cp -r sourcedir/ destdir/      # 复制目录,-r表示递归

# mv:移动/重命名文件
mv oldname.txt newname.txt     # 同目录下用作重命名
mv file.txt /tmp/              # 跨目录移动

# rm:删除文件/目录
rm filename                    # 删除文件
rm -r dirname                  # 删除目录,递归
rm -rf dirname                 # 强制递归删除,不确认(危险,慎用)

# which:查看命令的实际路径
which git                      # 查看git命令对应的可执行文件在哪

# find:按条件查找文件
find /path -size -10k          # 查找小于10KB的文件(-小于 +大于 不带符号等于)
find /path -size +100M         # 查找大于100MB的文件
find /tmp -type f -mtime +7    # 查找7天没修改过的文件(常用于清理脚本)
```

## 今日重点疑问梳理

### 1. touch的时间戳更新有什么实际意义?
不只是"创建空文件",更重要的用途是**配合依赖时间戳判断的自动化机制**:
- **make构建系统**:判断源文件比目标文件新,决定要不要重新编译
- **logrotate/清理脚本**(如 `find -mtime`):判断文件多久没改过,决定是否清理/轮转
- **Nginx缓存**:文件的Last-Modified时间影响浏览器缓存判断
- 也常用于**创建锁文件/标记文件**(比如 `touch /tmp/backup.lock`),这种场景靠的是"文件存不存在",不是时间戳

### 2. find的报错排查(/size写法)
`-size` 必须带横杠且紧跟大小值,否则find会把参数当成路径或者不认识的"断言":
```bash
find / -size -10k       # ✅ 正确
find /size -10k         # ❌ /size被当成路径
find / size -10k        # ❌ size前面少了横杠
```

### 3. find扫描/proc目录时报"没有那个文件或目录"是什么情况?
正常现象,不是命令写错。`/proc` 是内核实时生成的虚拟文件系统,find扫描到某个进程文件和真正去读取之间存在时间差,进程可能已结束,导致文件"消失",报错属于正常噪音。

**解决/优化写法**:
```bash
find / -size +100M 2>/dev/null   # 把报错(stderr)丢弃,只看正常结果
```

### 4. 2>/dev/null 到底在做什么?
Linux命令有三个输出通道:
| 编号 | 名称 | 作用 |
|---|---|---|
| 0 | stdin(标准输入) | 命令接收输入 |
| 1 | stdout(标准输出) | 正常执行结果 |
| 2 | stderr(标准错误) | 报错信息 |

`2>/dev/null` = 把2号通道(报错信息)重定向到 `/dev/null`(丢弃,不显示)。

常见变体:
```bash
command > file.txt        # 结果存文件
command 2> error.txt      # 报错存文件
command > file.txt 2>&1   # 结果+报错都存同一文件
command &> all.txt        # 上面的简写
```

### 5. /dev/null 是文件夹吗?能cd进去吗?
不能。`/dev/null` 是**字符设备文件**(`ls -l` 显示类型为 `c`),不是目录:
- 写入它 → 数据直接丢弃,不占空间
- 读取它 → 永远读到空

本质是系统提供的"丢弃数据的接口",不是能存放东西的"地方"。

## 踩坑记录
- 问题:`find /size -10k` 报错"未知的断言"
  原因:少了横杠,`/size` 被当成路径而不是参数
  解决:改成 `find / -size -10k`
- 问题:`cd /dev/null` 报错"不是目录"
  原因:`/dev/null` 是设备文件,不是目录
  解决:理解清楚它的性质即可,本来就不该cd进去

## 今日总结
掌握了文件查看/复制/移动/删除的基础命令, 都是大学学过的 没什么好说的 并且理解了touch的时间戳机制、find的size查找语法、以及stderr重定向(2>/dev/null)在实际运维排障中的用途。/proc是动态生成的特殊文件系统这一点也理清楚了。