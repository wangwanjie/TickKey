"""在 LLDB 中捕获主线程停顿时的符号栈，不求值表达式、不读取参数或局部变量。"""

import time

import lldb

_breakpoint_id = None
_captured = 0
_last_capture = 0.0
_maximum_captures = 8


def capture(frame, breakpoint_location, internal_dict):
    """后台心跳告警处短暂停下进程，读取各线程栈后自动继续。"""
    global _captured, _last_capture
    now = time.monotonic()
    if _captured >= _maximum_captures or now - _last_capture < 3:
        return False
    _captured += 1
    _last_capture = now
    process = frame.GetThread().GetProcess()
    target = process.GetTarget()
    print(f"[TickKeyHang] capture={_captured} time={time.strftime('%Y-%m-%d %H:%M:%S')} "
          f"threads={process.GetNumThreads()}")
    threads = sorted(list(process), key=lambda thread: thread.GetIndexID())
    for thread in threads[:32]:
        print(f"[TickKeyHang] thread #{thread.GetIndexID()} queue={thread.GetQueueName() or '-'}")
        limit = 96 if thread.GetIndexID() == 1 else 48
        for index in range(min(thread.GetNumFrames(), limit)):
            entry = thread.GetFrameAtIndex(index)
            address = entry.GetPCAddress().GetLoadAddress(target)
            module = entry.GetModule().GetFileSpec().GetFilename() or "?"
            symbol = entry.GetFunctionName() or "<unsymbolicated>"
            line = entry.GetLineEntry()
            source = ""
            if line.IsValid():
                source = f" at {line.GetFileSpec().GetFilename()}:{line.GetLine()}"
            print(f"[TickKeyHang]   #{index} 0x{address:x} {module}`{symbol}{source}")
    print("[TickKeyHang] end; automatically continuing")
    if _captured >= _maximum_captures:
        breakpoint_location.GetBreakpoint().SetEnabled(False)
        print("[TickKeyHang] capture limit reached; run tickkey-hangs to re-enable")
    return False


def enable(debugger, command, result, internal_dict):
    """重复启用会替换本脚本创建的断点，并重新开始最多八次采样。"""
    global _breakpoint_id, _captured, _last_capture
    target = debugger.GetSelectedTarget()
    if not target.IsValid():
        result.SetError("请先在 Xcode 启动 TickKey 的 Debug 调试会话。")
        return
    owned = [item.GetID() for item in target.breakpoint_iter() if item.MatchesName("TickKeyHangCapture")]
    for identifier in owned:
        target.BreakpointDelete(identifier)
    breakpoint = target.BreakpointCreateByRegex(r"^TickKey\.MainThreadMonitor\..*reportStall")
    breakpoint.AddName("TickKeyHangCapture")
    breakpoint.SetScriptCallbackFunction(__name__ + ".capture")
    _breakpoint_id = breakpoint.GetID()
    _captured = 0
    _last_capture = 0.0
    result.AppendMessage(
        f"TickKey 卡顿采样已启用：断点 {_breakpoint_id}，已匹配 {breakpoint.GetNumLocations()} 处。"
        "每次停顿自动输出 [TickKeyHang] 并继续运行，最多采样 8 次。"
        "若当前匹配为 0，请确认已编译包含 reportStall 的 Debug 版本；模块加载后断点会重新解析。")


def __lldb_init_module(debugger, internal_dict):
    """导入脚本即启用，不更改用户的全局 LLDB 配置。"""
    debugger.HandleCommand(f"command script add -f {__name__}.enable tickkey-hangs")
    debugger.HandleCommand("tickkey-hangs")
