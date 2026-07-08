/**
 * bridge_init.h — 原生函数注册入口头文件
 */
#ifndef BRIDGE_INIT_H
#define BRIDGE_INIT_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 原生函数注册扩展入口。
 * 在 QuickJS 上下文创建后调用，用于注册额外的 __native* 全局对象。
 * 当前为桩函数，所有注册在 quickjs_bridge.c 中完成。
 */
void bridge_init(void *ctx);

#ifdef __cplusplus
}
#endif

#endif /* BRIDGE_INIT_H */
