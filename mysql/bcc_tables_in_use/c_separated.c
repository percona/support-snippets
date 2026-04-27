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