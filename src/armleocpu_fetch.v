module armleocpu_fetch(
    input                   clk,
    input                   rst_n,

    // IRQ/Exception Base address
    input [31:0]            csr_mtvec,

    // From debug
    input                   dbg_request,
    input                   dbg_set_pc,
    input                   dbg_exit_request,
    input [31:0]            dbg_pc,

    // To Debug
    output reg              dbg_mode,
    // async signal:
    output reg              dbg_done,





    // Cache IF
    input      [3:0]        c_response,
    input                   c_reset_done,

    output reg [3:0]        c_cmd,
    output wire [31:0]      c_address,
    input      [31:0]       c_load_data,

    input      [31:0]       csr_mtvec,


    input                   irq_timer_en,
    input                   irq_exti_en,

    input                   irq_timer,
    input                   irq_exti,
    
    // towards execute
    output reg [31:0]       f2e_instr,
    output reg [31:0]       f2e_pc,
    output reg              f2e_exc_start,
    output reg [31:0]       f2e_cause,

    // from execute
    input                   e2f_ready,
    input                   e2f_cmd,
    input      [31:0]       e2f_bubble_branch_target,
    input      [31:0]       e2f_branchtarget,


);

parameter RESET_VECTOR = 32'h0000_2000;

`include "armleocpu_cache.inc"
`include "ld_type.inc"
`include "armleocpu_exception.inc"
`include "armleocpu_privilege.inc"
`include "armleocpu_e2f_cmd.inc"

`define INSTRUCTION_NOP ({12'h0, 5'h0, 3'b000, 5'h0, 7'b00_100_11});

/*STATE*/
reg [31:0] pc;
reg flushing;
reg bubble;
reg [31:0] saved_instr;
/*SIGNALS*/
reg [31:0] pc_nxt;
reg flushing_nxt;
reg bubble_nxt;
reg dbg_mode_nxt;

wire new_fetch_begin =
                    (dbg_mode && dbg_exit_request && (cache_idle || cache_done)) ||
                    (e2f_ready && (cache_done || cache_idle || cache_error));
wire cache_done = c_response == `CACHE_RESPONSE_DONE;
wire cache_error =  (c_response == `CACHE_RESPONSE_ACCESSFAULT) ||
                    (c_response == `CACHE_RESPONSE_MISSALIGNED) ||
                    (c_response == `CACHE_RESPONSE_PAGEFAULT);
wire cache_idle =   (c_response == `CACHE_RESPONSE_IDLE);
wire cache_wait =   (c_response == `CACHE_RESPONSE_WAIT);
wire pc_plus_4 = pc + 4;


assign c_address = pc_nxt;

always @(posedge clk)
    flushing <= flushing_nxt;

always @(posedge clk)
    bubble <= bubble_nxt;

always @(posedge clk)
    pc <= pc_nxt;

always @(posedge clk)
    saved_instr <= f2e_instr;

// reg dbg_mode;
always @(posedge clk)
    dbg_mode <= dbg_mode_nxt;

/*
always @* begin
    f2e_cause = 0;
    if(e2f_exc_start) begin
        
    end else if(c_response == `CACHE_RESPONSE_MISSALIGNED) begin
        f2e_cause = `EXCEPTION_CODE_INSTRUCTION_ADDRESS_MISALIGNED;
    end else if(c_response == `CACHE_RESPONSE_ACCESSFAULT) begin
        f2e_cause = `EXCEPTION_CODE_INSTRUCTION_ACCESS_FAULT;
    end else if(c_response == `CACHE_RESPONSE_PAGEFAULT) begin
        f2e_cause = `EXCEPTION_CODE_INSTRUCTION_PAGE_FAULT;
    end else if(irq_exti) begin
        f2e_cause = `EXCEPTION_CODE_EXTERNAL_INTERRUPT;
    end else if(irq_timer) begin
        f2e_cause = `EXCEPTION_CODE_TIMER_INTERRUPT;
    end
end
*/

/*

if dbg_mode ->
    output NOP
else if cache_wait -> NOP
else if cache_done ->
    if flushing -> NOP
    else -> output data from cache
else if idle ->
    if saved_valid -> output saved_instr
    else -> output NOP
else if error ->
    output NOP, start Exception
*/


always @* begin
    f2e_instr = `INSTRUCTION_NOP;
    f2e_pc = pc;
    if(!c_reset_done) begin
        
    end else begin
        // Output instr logic
        if (dbg_mode) begin
            // NOP
        end else if(cache_wait) begin
            // NOP
        end else if(cache_done) begin
            if(flushing)
                // NOP
            else
                f2e_instr = c_load_data;
        end else if(cache_idle) begin
            if(!bubble)
                f2e_instr = saved_instr;
            else
                // NOP
        end else if(cache_error) begin
            // NOP
        end
        // TODO: Add check for else
    end
end


/*
Command logic
    state:
        dbg_mode = 0, flushing = 0, bubble = 1, pc = reset_vector
    
    if dbg_mode && !dbg_exit_request
        -> debug mode, handle debug commands;
        if dbg_set_pc then set bubble to 1
    else if flushing
        if(cache_done) ->
            send NOP
            set flushing to zero
        else ->
            send flush
    else if bubble && cache_idle
        start fetching from pc
        bubble = 0
    esle if new_fetch_begin
        if dbg_request ->
            dbg_mode = 1
        else if irq && irq_enabled ->
            bubble = 1
            pc_nxt = mtvec
            start_exception(INTERRUPT);
        else if e2f_exc_start
            bubble = 1
            pc_nxt = mtvec
        else if e2f_exc_mret
            bubble = 1
            pc_nxt = mepc
        else if e2f_exc_sret
            bubble = 1
            pc_nxt = sepc
        else if e2f_branchtaken
            pc_nxt = branchtarget
        else if e2f_flush
            bubble = 1
            pc_nxt = pc + 4
            cmd = flush
            flushing = 1
        else if cache_error
            buble = 1
            pc_nxt = mtvec
            start_exception(FETCH_ERROR)
        else
            pc_nxt = pc + 4
    else
        continue fetching from pc
    new_fetch_begin =   (dbg_mode && dbg_exit_request && (cache_idle || cache_done)) ||
                        (e2f_ready && (cache_done || cache_idle || cache_error)) ||
    
*/



always @* begin
    pc_nxt = pc;
    bubble_nxt = bubble;
    dbg_mode_nxt = dbg_mode;
    c_cmd = `CACHE_CMD_NONE;
    f2e_exc_start = 1'b0;
    f2e_cause = 0;
    dbg_done = 0;

    if (dbg_mode && !dbg_exit_request) begin
        dbg_done = cache_done;
        if(dbg_set_pc) begin
            pc_nxt = dbg_pc;
            bubble_nxt = 1;
            dbg_done = 1;
        end
    end else if (flushing) begin
        if (cache_done) begin
            // CMD = NONE
            flushing_nxt = 0;
        end else begin
            c_cmd = `CACHE_CMD_FLUSH_ALL;
        end
    end else if(bubble && cache_idle) begin
        c_cmd = `CACHE_CMD_EXECUTE;
        pc_nxt = pc;
    end else if (new_fetch_begin) begin
        if (dbg_request) begin
            dbg_mode_nxt = 1;
        end else if(irq_exti && irq_exti_en) begin
            bubble_nxt = 1;
            pc_nxt = csr_mtvec;
            f2e_exc_start = 1'b1;
            f2e_cause = `EXCEPTION_CODE_EXTERNAL_INTERRUPT;
        end else if(irq_timer && irq_timer_en) begin
            bubble_nxt = 1;
            pc_nxt = csr_mtvec;
            f2e_exc_start = 1'b1;
            f2e_cause = `EXCEPTION_CODE_TIMER_INTERRUPT;
        end else if (e2f_cmd == `ARMLEOCPU_E2F_BUBBLE_BRANCH) begin
            bubble_nxt = 1;
            pc_nxt = e2f_bubble_branch_target;
        end else if (e2f_cmd == `ARMLEOCPU_E2F_FLUSH) begin
            bubble_nxt = 1;
            flushing_nxt = 1;
            pc_nxt = pc_plus_4;
        end else if (e2f_cmd == `ARMLEOCPU_E2F_BRANCHTAKEN) begin
            pc_nxt = e2f_branchtarget;
            c_cmd = `CACHE_CMD_EXECUTE;
        end else if (cache_error) begin
            bubble_nxt = 1;
            pc_nxt = csr_mtvec;
            f2e_exc_start = 1'b1;
            if(c_response == `CACHE_RESPONSE_MISSALIGNED) begin
                f2e_cause = `EXCEPTION_CODE_INSTRUCTION_ADDRESS_MISALIGNED;
            end else if(c_response == `CACHE_RESPONSE_ACCESSFAULT) begin
                f2e_cause = `EXCEPTION_CODE_INSTRUCTION_ACCESS_FAULT;
            end else if(c_response == `CACHE_RESPONSE_PAGEFAULT) begin
                f2e_cause = `EXCEPTION_CODE_INSTRUCTION_PAGE_FAULT;
            end
        end else begin
            pc_nxt = pc_plus_4;
            c_cmd = `CACHE_CMD_EXECUTE;
        end
    end else begin
        pc_nxt = pc;
        c_cmd = `CACHE_CMD_EXECUTE;
    end
end






/*
always @* begin
    pc_nxt = pc;
    c_cmd = `CACHE_CMD_NONE;
    f2e_exc_start = 1'b0;
    dbg_done = 0;
    flushing_nxt = flushing;
    saved_instr_nxt = saved_instr;
    if(!c_reset_done) begin
        
    end else begin
        // Command logic
        if(dbg_mode && !dbg_exit_request) begin
            dbg_done = cache_done;
            if(dbg_set_pc) begin
                //pc <= dbg_pc;
                dbg_done = 1;
            end
        end else if(flushing) begin
            if(!cache_done) begin
                c_cmd = `CACHE_CMD_FLUSH_ALL;
                flushing_nxt = 0; // WTF???
            end else begin
                // cmd = NONE
            end
        end else if(cache_wait) begin
            c_cmd = `CACHE_CMD_EXECUTE;
            //pc_nxt = pc;
        end else if(reseted || dbg_exit_request || cache_error || (e2f_ready && (cache_done || cache_idle))) begin
            c_cmd = `CACHE_CMD_EXECUTE;
            if (reseted) begin
                pc_nxt = RESET_VECTOR;
            end else if(dbg_request) begin
                c_cmd = `CACHE_CMD_NONE;
            end else if(irq_exti || irq_timer) begin
                f2e_exc_start = 1'b1;
                pc_nxt = csr_mtvec;
            end else if(e2f_exc_return) begin
                pc_nxt = e2f_exc_epc;
            end else if(e2f_branchtaken) begin
                pc_nxt = e2f_branchtarget;
            end else if(e2f_ready && e2f_flush) begin
                c_cmd = `CACHE_CMD_FLUSH_ALL;
            end else if(e2f_ready && e2f_exc_start) begin
                pc_nxt = csr_mtvec;
            end else if(cache_error) begin
                f2e_exc_start = 1'b1;
                pc_nxt = csr_mtvec;
            end else begin
                pc_nxt = pc + 4;
            end
        end
    end
    
end



always @(posedge clk) begin
    if(!rst_n) begin
        reseted <= 1'b1;
        flushing <= 1'b0;
        after_flush <= 1'b0;
        dbg_mode <= 1'b0;
    end else begin
        saved_instr <= f2e_instr;
        pc <= pc_nxt;
        if(!c_reset_done) begin
            // nothing to do
        end else begin
            // TODO:
            if(dbg_mode && !dbg_exit_request) begin
                if(dbg_set_pc) begin
                    `ifdef DEBUG_FETCH
                        $display("[%m][%d][Fetch] Debug requested set pc dbg_pc = 0x%X", $time, dbg_pc);
                    `endif
                    pc <= dbg_pc;
                    bubble <= 1;
                end
            end else if(flushing) begin
                if(!cache_done) begin
                    
                end else begin
                    `ifdef DEBUG_FETCH
                        $display("[%m][%d][Fetch] Flush done", $time);
                    `endif
                    flushing <= 1'b0;
                    after_flush <= 1'b1;
                end
            end else if(cache_wait) begin
                
            end else if(dbg_exit_request || reseted || cache_error || (e2f_ready && (cache_done || cache_idle))) begin
                `ifdef DEBUG_FETCH
                    if(dbg_exit_request)
                        $display("[%m][%d][Fetch] Exiting debug mode", $time);
                `endif
                after_flush <= 1'b0;
                reseted <= 1'b0;
                dbg_mode <= 1'b0;
                if (reseted) begin
                    `ifdef DEBUG_FETCH
                    $display("[%m][%d][Fetch] Starting fetch from reset vector", $time);
                    `endif
                end else if(dbg_request) begin
                    `ifdef DEBUG_FETCH
                    $display("[%m][%d][Fetch] Entering debug state", $time);
                    `endif
                    dbg_mode <= 1'b1;
                end else if(irq_exti || irq_timer) begin
                    `ifdef DEBUG_FETCH
                    $display("[%m][%d][Fetch] Starting interrupt: %s", $time, irq_timer ? "timer" : "exti");
                    `endif
                end else if(e2f_exc_return) begin
                    `ifdef DEBUG_FETCH
                    $display("[%m][%d][Fetch] Exception return: pc_nxt = 0x%x", $time, pc_nxt);
                    `endif
                end else if(e2f_branchtaken) begin
                    `ifdef DEBUG_FETCH
                    $display("[%m][%d][Fetch] Branch taken: 0x%X, pc_nxt = 0x%X", $time, e2f_branchtarget, pc_nxt);
                    `endif
                end else if(e2f_ready && e2f_flush) begin
                    `ifdef DEBUG_FETCH
                    $display("[%m][%d][Fetch] Starting flush", $time);
                    `endif
                    flushing <= 1'b1;
                end else if(e2f_ready && e2f_exc_start) begin
                    `ifdef DEBUG_FETCH
                    $display("[%m][%d][Fetch] Starting exception requested from execute", $time);
                    `endif
                end else if(cache_error) begin
                    `ifdef DEBUG_FETCH
                    $display("[%m][%d][Fetch] Starting fetch error, pc_nxt = 0x%X", $time, pc_nxt);
                    `endif
                end else begin
                    `ifdef DEBUG_FETCH
                    $display("[%m][%d][Fetch] Starting fetch pc+4; pc = 0x%X, pc_nxt=0x%X", $time, pc, pc_nxt);
                    `endif
                end
            end
        end
    end
end
*/

endmodule