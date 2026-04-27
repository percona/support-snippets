#!/usr/bin/python

from __future__ import print_function
from bcc import BPF
from bcc.utils import printb
import errno
from functools import partial
import sys

debug = False

bpf_text = """
#include <uapi/linux/ptrace.h>
#include <linux/bpf.h>

struct trx_t {
    char pad0[536]; 
    u32 n_mysql_tables_in_use;
};

struct row_prebuilt_t {
    char pad0[24]; 
    struct trx_t *trx;
};

struct ib_cursor_t {
    char pad0[80];
    struct row_prebuilt_t *prebuilt;
};

struct ha_innopart_t {
    char pad0[1248]; 
    struct row_prebuilt_t *prebuilt;
};

struct data_t {
    u32 n_mysql_tables_in_use;
    u32 tid;
    u64 tgid_pid;
    u64 stack_id;
    u64 trx_ptr;     // DEBUG: pointer to trx validation
    u32 read_error;  // Error flag for read operation
    u32 validate_error; // Set true if tables in use is not 0
    u32 sentinel_error; // Set true if sentinel error is detected
};

BPF_PERF_OUTPUT(events);
BPF_STACK_TRACE(stacks, 16384);

int trace_func_trx_r14(struct pt_regs *ctx) {
    struct data_t data = {};
    data.tgid_pid = bpf_get_current_pid_tgid();
    data.tid = (u32)data.tgid_pid;
    data.stack_id = stacks.get_stackid(ctx, BPF_F_USER_STACK);
    data.validate_error = 0;

    
    // Capture pointer for debug
    data.trx_ptr = (u64)ctx->r14;
    data.read_error = 0;

    bpf_trace_printk("trace_func_trx_r14: %llx\\n", data.trx_ptr);
    
    // Validate pointer before using
    if (ctx->r14 == 0) {
        data.sentinel_error = 0xFFFFFFFF; // Sentinel: NULL pointer
        data.read_error = 1;
    } else {
        struct trx_t *trx = (struct trx_t *)ctx->r14;
        
        // Use bpf_probe_read_user for safe read
        if (bpf_probe_read_user(&data.n_mysql_tables_in_use, 
                               sizeof(u32), 
                               &trx->n_mysql_tables_in_use) != 0) {
            data.sentinel_error = 0xEEEEEEEE; // Sentinel: read error
            data.read_error = 2;
        }
    }

    events.perf_submit(ctx, &data, sizeof(data));
    return 0;
}

int trace_func_cursor_di(struct pt_regs *ctx) {
    struct data_t data = {};
    data.tgid_pid = bpf_get_current_pid_tgid();
    data.tid = (u32)data.tgid_pid;
    data.stack_id = stacks.get_stackid(ctx, BPF_F_USER_STACK);
    data.validate_error = 0;

    
    // Capture pointer for debug
    data.trx_ptr = (u64)ctx->di;
    data.read_error = 0;
    
    // Validate pointer before using
    if (ctx->di == 0) {
        data.sentinel_error = 0xFFFFFFFF; // Sentinel: NULL pointer
        data.read_error = 1;
    } else {
        struct ib_cursor_t *cursor = (struct ib_cursor_t *)ctx->di;
        
        // Use bpf_probe_read_user for safe read
        if (bpf_probe_read_user(&data.n_mysql_tables_in_use, 
                               sizeof(u32), 
                               &cursor->prebuilt->trx->n_mysql_tables_in_use) != 0) {
            data.sentinel_error = 0xEEEEEEEE; // Sentinel: read error
            data.read_error = 2;
        }
    }

    events.perf_submit(ctx, &data, sizeof(data));
    return 0;
}

int trace_func_cursor_bx(struct pt_regs *ctx) {
    struct data_t data = {};
    data.tgid_pid = bpf_get_current_pid_tgid();
    data.tid = (u32)data.tgid_pid;
    data.stack_id = stacks.get_stackid(ctx, BPF_F_USER_STACK);
    data.validate_error = 0;

    
    // Capture pointer for debug
    data.trx_ptr = (u64)ctx->bx;
    data.read_error = 0;
    
    // Validate pointer before using
    if (ctx->bx == 0) {
        data.sentinel_error = 0xFFFFFFFF; // Sentinel: NULL pointer
        data.read_error = 1;
    } else {
        struct ib_cursor_t *cursor = (struct ib_cursor_t *)ctx->bx;
        
        //Use bpf_probe_read_user for safe read
        if (bpf_probe_read_user(&data.n_mysql_tables_in_use, 
                               sizeof(u32), 
                               &cursor->prebuilt->trx->n_mysql_tables_in_use) != 0) {
            data.sentinel_error = 0xEEEEEEEE; // Sentinel: read error
            data.read_error = 2;
        }
    }

    events.perf_submit(ctx, &data, sizeof(data));
    return 0;
}


int trace_func_cursor_dx(struct pt_regs *ctx) {
    struct data_t data = {};
    data.tgid_pid = bpf_get_current_pid_tgid();
    data.tid = (u32)data.tgid_pid;
    data.stack_id = stacks.get_stackid(ctx, BPF_F_USER_STACK);
    data.validate_error = 0;

    
    // Capture pointer for debug
    data.trx_ptr = (u64)ctx->dx;
    data.read_error = 0;
    
    // Validate pointer before using
    if (ctx->dx == 0) {
        data.sentinel_error = 0xFFFFFFFF; // Sentinel: NULL pointer
        data.read_error = 1;
    } else {
        struct ib_cursor_t *cursor = (struct ib_cursor_t *)ctx->dx;
        
        //Use bpf_probe_read_user for safe read
        if (bpf_probe_read_user(&data.n_mysql_tables_in_use, 
                               sizeof(u32), 
                               &cursor->prebuilt->trx->n_mysql_tables_in_use) != 0) {
            data.sentinel_error = 0xEEEEEEEE; // Sentinel: read error
            data.read_error = 2;
        }
    }

    events.perf_submit(ctx, &data, sizeof(data));
    return 0;
}

int trace_func_ha_innopart_bx(struct pt_regs *ctx) {
   struct data_t data = {};
    data.tgid_pid = bpf_get_current_pid_tgid();
    data.tid = (u32)data.tgid_pid;
    data.stack_id = stacks.get_stackid(ctx, BPF_F_USER_STACK);
    data.validate_error = 0;

    
    // Capture pointer for debug
    data.trx_ptr = (u64)ctx->bx;
    data.read_error = 0;
    
    // Validate pointer before using
    if (ctx->bx == 0) {
        data.sentinel_error = 0xFFFFFFFF; // Sentinel: NULL pointer
        data.read_error = 1;
    } else {
        struct ha_innopart_t *ha_innopart = (struct ha_innopart_t *)ctx->bx;
        
        //Use bpf_probe_read_user for safe read
        if (bpf_probe_read_user(&data.n_mysql_tables_in_use, 
                               sizeof(u32), 
                               &ha_innopart->prebuilt->trx->n_mysql_tables_in_use) != 0) {
            data.sentinel_error = 0xEEEEEEEE; // Sentinel: read error
            data.read_error = 2;
        }
    }

    events.perf_submit(ctx, &data, sizeof(data));
    return 0;
}

int trace_func_row_prebuilt_dx(struct pt_regs *ctx) {
   struct data_t data = {};
    data.tgid_pid = bpf_get_current_pid_tgid();
    data.tid = (u32)data.tgid_pid;
    data.stack_id = stacks.get_stackid(ctx, BPF_F_USER_STACK);
    data.validate_error = 0;

    
    // Capture pointer for debug
    data.trx_ptr = (u64)ctx->dx;
    data.read_error = 0;
    
    // Validate pointer before using
    if (ctx->dx == 0) {
        data.sentinel_error = 0xFFFFFFFF; // Sentinel: NULL pointer
        data.read_error = 1;
    } else {
        struct row_prebuilt_t *row_prebuilt = (struct row_prebuilt_t *)ctx->dx;
        
        //Use bpf_probe_read_user for safe read
        if (bpf_probe_read_user(&data.n_mysql_tables_in_use, 
                               sizeof(u32), 
                               &row_prebuilt->trx->n_mysql_tables_in_use) != 0) {
            data.sentinel_error = 0xEEEEEEEE; // Sentinel: read error
            data.read_error = 2;
        }
    }

    events.perf_submit(ctx, &data, sizeof(data));
    return 0;
}

int trace_validate(struct pt_regs *ctx) {
    struct data_t data = {};
    data.tgid_pid = bpf_get_current_pid_tgid();
    data.tid = (u32)data.tgid_pid;
    data.stack_id = stacks.get_stackid(ctx, BPF_F_USER_STACK);
    
    //Setting validate_error to 2 to indicate that we hit the validate free function probe
    //And didn't reach the table in use != 0, so we can clean this thread id from the list
    data.validate_error = 2;
    
    // Capture pointer for debug
    data.trx_ptr = (u64)ctx->bx;
    data.read_error = 0;
    
    // Validate pointer before using
    if (ctx->bx == 0) {
        data.sentinel_error = 0xFFFFFFFF; // Sentinel: NULL pointer
        data.read_error = 1;
    } else {
        struct trx_t *trx = (struct trx_t *)ctx->bx;
        
        //Use bpf_probe_read_user for safe read
        if (bpf_probe_read_user(&data.n_mysql_tables_in_use, 
                               sizeof(u32), 
                               &trx->n_mysql_tables_in_use) != 0) {
            data.sentinel_error = 0xEEEEEEEE; // Sentinel: read error
            data.read_error = 2;
        }
    }
    
    if (data.n_mysql_tables_in_use != 0) {
        data.validate_error = 1;
    }

    events.perf_submit(ctx, &data, sizeof(data));
    return 0;
}

int print_trace_func(struct pt_regs *ctx) {
    bpf_trace_printk("print_trace_func\\n");
    return 0;
}
"""
# load BPF program
try:
    b = BPF(text=bpf_text)
    print("[OK] BPF program loaded successfully")
except Exception as e:
    print(f"[ERROR] Failed to load BPF program: {e}")
    exit(1)

# Attach probes with error handling
try:

    received_pid = -1
    if len(sys.argv) >= 2:
        received_pid = int(sys.argv[1], 10)
    else:
        print("[ERROR] No PID provided, please run the script with the PID of the MySQL process")
        exit(1)

    b.attach_uprobe(name="/opt/percona_server/8.4.7/bin/mysqld", sym="_ZN11ha_innobase13external_lockEP3THDi", sym_off=770, fn_name="trace_func_trx_r14", pid=received_pid)
    b.attach_uprobe(name="/opt/percona_server/8.4.7/bin/mysqld", sym="_ZN11ha_innobase13external_lockEP3THDi", sym_off=1254, fn_name="trace_func_trx_r14", pid=received_pid)
    b.attach_uprobe(name="/opt/percona_server/8.4.7/bin/mysqld", sym="_Z15ib_cursor_resetP11ib_cursor_t", sym_off=45, fn_name="trace_func_cursor_di", pid=received_pid)
    b.attach_uprobe(name="/opt/percona_server/8.4.7/bin/mysqld", sym="_Z15ib_cursor_closeP11ib_cursor_t", sym_off=46, fn_name="trace_func_cursor_bx", pid=received_pid)
    b.attach_uprobe(name="/opt/percona_server/8.4.7/bin/mysqld", sym="_ZN11ha_innopart13external_lockEP3THDi", sym_off=516, fn_name="trace_func_ha_innopart_bx", pid=received_pid)
    b.attach_uprobe(name="/opt/percona_server/8.4.7/bin/mysqld", sym="_ZL16ib_create_cursorPP11ib_cursor_tP12dict_table_tP12dict_index_tP5trx_t.lto_priv.0", sym_off=315, fn_name="trace_func_row_prebuilt_dx", pid=received_pid)
    #Validation probe
    b.attach_uprobe(name="/opt/percona_server/8.4.7/bin/mysqld", sym="_ZL30trx_validate_state_before_freeP5trx_t.lto_priv.0", sym_off=273, fn_name="trace_validate", pid=received_pid)



    print("[OK] All probes attached successfully")
except Exception as e:
    print(f"[ERROR] Failed to attach probes: {e}")
    print("[TIP] Verify:")
    print("   - MySQL PID is correct (ps aux | grep mysqld)")
    print("   - Binary path exists")
    print("   - Symbol names are correct (objdump -t)")
    exit(1)

print("Attached. Run workload that hits the probe; Ctrl-C to stop.")

def stack_id_err(stack_id):
    # -EFAULT in get_stackid normally means the stack-trace is not available,
    # Such as getting kernel stack trace in userspace code
    return (stack_id < 0) and (stack_id != -errno.EFAULT)

def print_stack(bpf, stack_id, tgid):
    try:
        stacks = list(bpf.get_table("stacks").walk(stack_id))
        for addr in stacks:
            print("        ", end="")
            print("%s" % (bpf.sym(addr, tgid, show_module=True, show_offset=True)))
    except Exception as e:
        print(f"        [Stack trace error: {e}]")

def print_event_from_bpf(cpu, data, size):
    event = b["events"].event(data)
    
    # Validar e interpretar dados extraídos
    if hasattr(event, 'read_error') and event.read_error > 0:
        if event.read_error == 1:
            print(f"[WARNING] NULL POINTER: TID={event.tid}, TRX=0x{event.trx_ptr:x}")
        elif event.read_error == 2:
            print(f"[WARNING] READ ERROR: TID={event.tid}, TRX=0x{event.trx_ptr:x}")
        return
    
    # Verificar valores suspeitos
    if event.sentinel_error == 0xFFFFFFFF:
        print(f"[WARNING] NULL POINTER DETECTED: TID={event.tid}")
        return
    elif event.sentinel_error == 0xEEEEEEEE:
        print(f"[WARNING] READ ERROR DETECTED: TID={event.tid}")
        return
    elif event.sentinel_error > 1000:
        print(f"[WARNING] SUSPICIOUS VALUE: {event.sentinel_error} tables (TID={event.tid})")
        return
        
    if event.validate_error == 1 or debug == True:
    # Stack trace apenas se dados válidos
        if not stack_id_err(event.stack_id):
            # Dados válidos - mostrar informações
            print(f"[VALIDATE] TID={event.tid} | Tables in use: {event.n_mysql_tables_in_use} | TRX=0x{event.trx_ptr:x}")
            print_stack(b, event.stack_id, event.tgid_pid)
            print()
            print("------------------------------------------------------------")
            print()
       
        else:
            print("   [Stack trace unavailable]")
        return
    
# Configurar buffer de events
try:
    b["events"].open_perf_buffer(print_event_from_bpf)
    print("[OK] Event buffer configured")
except Exception as e:
    print(f"[ERROR] Failed to configure event buffer: {e}")
    exit(1)

try:
    while True:
        b.perf_buffer_poll()
except KeyboardInterrupt:
    pass
