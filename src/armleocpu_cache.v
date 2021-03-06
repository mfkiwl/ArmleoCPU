
//`timescale 1ns/1ns


`include "armleocpu_defines.vh"

module armleocpu_cache (
    input                   clk,
    input                   rst_n,

    //                      CACHE <-> EXECUTE/MEMORY
    /* verilator lint_off UNOPTFLAT */
    output reg   [3:0]      c_response, // CACHE_RESPONSE_*
    /* verilator lint_on UNOPTFLAT */
    output wire             c_reset_done,

    input  [3:0]            c_cmd, // CACHE_CMD_*
    input  [31:0]           c_address,
    input  [2:0]            c_load_type, // enum defined in ARMLEOCPU_defs LOAD_*
    output wire  [31:0]     c_load_data,
    input [1:0]             c_store_type, // enum defined in ARMLEOCPU_defs STORE_*
    input [31:0]            c_store_data,

    //                      CACHE <-> CSR
    //                      More in docs/
    //                      SATP from RISC-V privileged spec registered on FLUSH_ALL or SFENCE_VMA
    input                   csr_satp_mode, // Mode = 0 -> physical access,
                                           // 1 -> ppn valid
    input [21:0]            csr_satp_ppn,
    
    //                      MPRV from RISC-V privileged spec
    input                   csr_mstatus_mprv,
    //                      MXR from RISC-V privileged spec
    input                   csr_mstatus_mxr,
    //                      SUM from RISC-V privileged spec
    input                   csr_mstatus_sum,
    //                      MPP from RISC-V privileged spec
    input [1:0]             csr_mstatus_mpp,

    //                      MPRV from armleocpu Extension
    input [1:0]             csr_mcurrent_privilege,


    
    //                      CACHE <-> MEMORY
    output reg              m_transaction,
    output reg   [2:0]      m_cmd,         // enum `ARMLEOBUS_CMD_*
    input                   m_transaction_done,
    input        [2:0]      m_transaction_response, // enum `ARMLEOBUS_RESPONSE_*
    output reg   [33:0]     m_address,
    output reg   [3:0]      m_burstcount,
    output reg   [31:0]     m_wdata,
    output reg   [3:0]      m_wbyte_enable,
    input        [31:0]     m_rdata
);

// |------------------------------------------------|
// |                                                |
// |              Parameters and includes           |
// |                                                |
// |------------------------------------------------|
//`define DEBUG_CACHE_PTAG
//`define DEBUG_CACHE_LANESTATE_WRITE
//`define DEBUG_CACHE_LANESTATE_READ

parameter WAYS_W = 2;
localparam WAYS = 2**WAYS_W;

parameter TLB_ENTRIES_W = 4;
parameter TLB_WAYS_W = 2;
localparam TLB_ENTRIES = 2**TLB_ENTRIES_W;
parameter BYPASS_ENABLED = 0;
// TODO:

localparam LANES_W = 6;
localparam LANES = 2**LANES_W;

localparam PHYS_W = 22;
localparam VIRT_W = 20;

// 4 = 16 words each 32 bit = 64 byte
localparam OFFSET_W = 4;
localparam WORDS_IN_LANE = 2**OFFSET_W;





// |------------------------------------------------|
// |                                                |
// |              Cache State                       |
// |                                                |
// |------------------------------------------------|

reg [3:0] state;
reg [3:0] return_state;
localparam 	STATE_RESET = 4'd0,
            STATE_ACTIVE = 4'd1,
            STATE_FLUSH = 4'd2,
            STATE_REFILL = 4'd3,
            STATE_FLUSH_ALL = 4'd4,
            STATE_PTW = 4'd5;

reg [1:0] substate;
localparam  SUBSTATE_FLUSH_ALL_INITIAL = 2'd0,
            SUBSTATE_FLUSH_ALL_TLB_INVALIDATE = 2'd1,
            SUBSTATE_FLUSH_ALL_FETCH = 2'd2,
            SUBSTATE_FLUSH_ALL_DECIDE = 2'd3;


// reset state
reg [LANES_W-1:0]           reset_lane_counter;
// reset state + flush_all state
reg [TLB_ENTRIES_W-1:0]     tlb_invalidate_set_index;



reg [OFFSET_W-1:0]          os_word_counter;
reg [WAYS_W-1:0]            flush_current_way;
// flush state
reg                         flush_initial_done;

// flush_all current lane
// counts until from 0 to LANES (included)
reg [LANES_W:0]           flush_all_current_lane;


// |------------------------------------------------|
// |                                                |
// |              Output stage                      |
// |                                                |
// |------------------------------------------------|
reg                         os_active;
reg                         os_error;
reg                         os_error_type;

//                          address decomposition
reg [VIRT_W-1:0]            os_address_vtag; // Used by PTW
reg [LANES_W-1:0]           os_address_lane;
reg [OFFSET_W-1:0]          os_address_offset;
reg [1:0]                   os_address_inword_offset;



reg [3:0]                   os_cmd;
reg [2:0]                   os_load_type;
reg [1:0]                   os_store_type;

`ifdef DEBUG_CACHE
    /*verilator coverage_off*/
    reg [7*8-1:0] c_cmd_ascii;
    always @* begin
        case(c_cmd)
            `CACHE_CMD_LOAD:        c_cmd_ascii = "LOAD";
            `CACHE_CMD_EXECUTE:     c_cmd_ascii = "EXECUTE";
            `CACHE_CMD_STORE:       c_cmd_ascii = "STORE";
            `CACHE_CMD_FLUSH_ALL:   c_cmd_ascii = "FLUSH";
            default:                c_cmd_ascii = "UNKNOWN";
        endcase
    end

    reg [7*8-1:0] os_cmd_ascii;
    always @* begin
        case(os_cmd)
            `CACHE_CMD_LOAD:        os_cmd_ascii = "LOAD";
            `CACHE_CMD_EXECUTE:     os_cmd_ascii = "EXECUTE";
            `CACHE_CMD_STORE:       os_cmd_ascii = "STORE";
            `CACHE_CMD_FLUSH_ALL:   os_cmd_ascii = "FLUSH";
            default:                os_cmd_ascii = "UNKNOWN";
        endcase
    end
    reg [3*8-1:0] os_load_type_ascii;
    always @* begin
        case (os_load_type)
            `LOAD_BYTE:
                os_load_type_ascii = "lb";
            `LOAD_BYTE_UNSIGNED:
                os_load_type_ascii = "lbu";
            `LOAD_HALF:
                os_load_type_ascii = "lh";
            `LOAD_HALF_UNSIGNED:
                os_load_type_ascii = "lhu";
            `LOAD_WORD:
                os_load_type_ascii = "lw";
            default:
                os_load_type_ascii = "???";
        endcase
    end
    
    reg [2*8-1:0] os_store_type_ascii;
    always @* begin
        case (os_store_type)
            `STORE_BYTE:
                os_store_type_ascii = "sb";
            `STORE_HALF:
                os_store_type_ascii = "sh";
            `STORE_WORD:
                os_store_type_ascii = "sw";
            default:
                os_store_type_ascii = "??";
        endcase
    end

    reg[11*8-1:0] c_response_ascii;
    always @* begin
        case (c_response)
            `CACHE_RESPONSE_IDLE:        c_response_ascii = "IDLE";
            `CACHE_RESPONSE_DONE:        c_response_ascii = "DONE";
            `CACHE_RESPONSE_WAIT:        c_response_ascii = "WAIT";
            `CACHE_RESPONSE_MISSALIGNED: c_response_ascii = "MISSALIGNED";
            `CACHE_RESPONSE_PAGEFAULT:   c_response_ascii = "PAGEFAULT";
            `CACHE_RESPONSE_UNKNOWNTYPE: c_response_ascii = "UNKNOWNTYPE";
            `CACHE_RESPONSE_ACCESSFAULT: c_response_ascii = "ACCESSFAULT";
            default:
                c_response_ascii = "???????????";
        endcase
    end
    /*verilator coverage_on*/
`endif

reg [31:0]                  os_store_data;


reg [WAYS_W-1:0]            victim_way;
reg                         csr_satp_mode_r;
reg [21:0]                  csr_satp_ppn_r;


// |------------------------------------------------|
// |                                                |
// |              Signals                           |
// |                                                |
// |------------------------------------------------|


// Lane tag storage
// Valid and Dirty bits = Lanestate
// PTAG is read when idle or flush_all
// Valid and dirty is read when idle or flush_all
// PTAG is written when in refill
// Valid and dirty is written when idle, refill, or flush

//                      PTAG Read port
reg                     ptag_read           [WAYS-1:0];
reg  [LANES_W-1:0]      ptag_readlane       [WAYS-1:0];
wire [PHYS_W-1:0]       ptag_readdata       [WAYS-1:0];

//                      PTAG Write port
reg                     ptag_write          [WAYS-1:0];
reg  [LANES_W-1:0]      ptag_writelane;
reg  [PHYS_W-1:0]       ptag_writedata;

//                      lanestate read port
reg                     lanestate_read           [WAYS-1:0];
reg  [LANES_W-1:0]      lanestate_readlane       [WAYS-1:0];
wire [WAYS-1:0]         lanestate_readdata       [1:0];
//                      lanestate write port
reg  [WAYS-1:0]         lanestate_write;
reg  [LANES_W-1:0]      lanestate_writelane;
reg  [1:0]              lanestate_writedata;
`ifdef DEBUG_CACHE
    `ifdef DEBUG_CACHE_LANESTATE_WRITE
        genvar lanestate_write_counter;
        generate
        for(lanestate_write_counter = 0; lanestate_write_counter < WAYS; lanestate_write_counter = lanestate_write_counter + 1) begin : lanestate_write_debug_for
            always @(posedge clk)
                if(lanestate_write[lanestate_write_counter]) begin
                    $display("[%m][%d] lanestate_write way = 0x%X, lane = 0x%X, data = 0x%X",
                            $time, lanestate_write_counter, lanestate_writelane, lanestate_writedata);
                end
        end
        endgenerate
    `endif
`endif

//                      Storage read port vars
reg  [WAYS-1:0]         storage_read;
reg  [LANES_W-1:0]      storage_readlane    [WAYS-1:0];
reg  [OFFSET_W-1:0]     storage_readoffset  [WAYS-1:0];
wire [31:0]             storage_readdata    [WAYS-1:0];
//                      Storage write port vars
reg  [WAYS-1:0]         storage_write;
reg  [3:0]              storage_byteenable;
reg  [31:0]             storage_writedata;
reg  [LANES_W-1:0]      storage_writelane;
reg  [OFFSET_W-1:0]     storage_writeoffset;


// PTW request signals
reg                     ptw_resolve_request;
reg  [19:0]             ptw_resolve_vtag;
// PTW result signals
wire                    ptw_resolve_done;
wire                    ptw_pagefault;
wire                    ptw_accessfault;

`ifdef DEBUG_PAGEFAULT
wire [30*8-1:0] pagefault_reason;
`endif

wire [7:0]              ptw_resolve_access_bits;
wire [PHYS_W-1:0]       ptw_resolve_phystag;

// PTW m_* signals
wire                    ptw_m_transaction;
wire [2:0]              ptw_m_cmd;
wire [33:0]             ptw_m_address;


// Store gen signals
wire [31:0]             storegen_dataout;
wire [3:0]              storegen_mask;
wire                    storegen_missaligned;
wire                    storegen_unknowntype;
// Load gen signals
/* verilator lint_off UNOPTFLAT */
reg                     loadgen_datain_sel;
/* verilator lint_on UNOPTFLAT */
reg [31:0]              loadgen_datain;
wire                    loadgen_missaligned;
wire                    loadgen_unknowntype;

reg  [1:0]              tlb_command;

// read port
reg  [19:0]             tlb_resolve_virtual_address;
wire                    tlb_hit;
wire [7:0]              tlb_read_accesstag;
wire [PHYS_W-1:0]       tlb_read_ptag;

// write port
reg  [19:0]             tlb_write_vtag;
reg  [7:0]              tlb_write_accesstag;
reg  [PHYS_W-1:0]       tlb_write_ptag;


// TODO: correctly handle vm_enabled csr_satp_mode_r
wire [1:0] vm_privilege = ((csr_mcurrent_privilege == `ARMLEOCPU_PRIVILEGE_MACHINE) && csr_mstatus_mprv) ? csr_mstatus_mpp : csr_mcurrent_privilege;
wire vm_enabled = (vm_privilege == `ARMLEOCPU_PRIVILEGE_SUPERVISOR || vm_privilege == `ARMLEOCPU_PRIVILEGE_USER) && csr_satp_mode_r;

wire access_request =   (c_cmd == `CACHE_CMD_EXECUTE) ||
                        (c_cmd == `CACHE_CMD_LOAD) ||
                        (c_cmd == `CACHE_CMD_STORE);

wire [VIRT_W-1:0] 	        c_address_vtag          = c_address[31:32-VIRT_W]; // Goes to TLB/PTW only
wire [LANES_W-1:0]	        c_address_lane          = c_address[2+OFFSET_W+LANES_W-1:2+OFFSET_W];
wire [OFFSET_W-1:0]			c_address_offset        = c_address[2+OFFSET_W-1:2];
wire [1:0]			        c_address_inword_offset = c_address[1:0];


reg                         stall; // Output stage stalls input stage
wire                        pagefault;
reg                         unknowntype;
reg                         missaligned;


wire [PHYS_W-1:0]           ptag;

// reset state
reg                         tlb_invalidate_done;
reg                         reset_valid_reset_done;

wire [WAYS-1:0]             os_valid_per_way = lanestate_readdata[0];
wire [WAYS-1:0]             os_dirty_per_way = lanestate_readdata[1];
wire                        os_victim_valid = os_valid_per_way[victim_way];
wire                        os_victim_dirty = os_dirty_per_way[victim_way] && os_valid_per_way[victim_way];

reg  [WAYS-1:0]             way_hit;
reg  [WAYS_W-1:0]           os_cache_hit_way;
reg                         os_cache_hit;
reg  [31:0]                 os_readdata;

wire flush_all_done = flush_all_current_lane == LANES;
reg [WAYS_W-1:0] flush_all_dirty_lane_way;
reg flush_all_any_lane_dirty;

assign c_reset_done = state != STATE_RESET;


genvar way_num;
genvar byte_offset;
generate
for(way_num = 0; way_num < WAYS; way_num = way_num + 1) begin : mem_generate_for
    mem_1w1r #(
        .ELEMENTS_W(LANES_W),
        .WIDTH(PHYS_W)
    ) ptag_storage (
        .clk(clk),
        
        .read(ptag_read[way_num]),
        .readaddress(ptag_readlane[way_num]),
        .readdata(ptag_readdata[way_num]),
        
        .write(ptag_write[way_num]),
        .writeaddress(ptag_writelane),
        .writedata(ptag_writedata)
    );
    
    mem_1w1r #(
        .ELEMENTS_W(LANES_W),
        .WIDTH(2)
    ) lanestatestorage (
        .clk(clk),
        
        .read(lanestate_read[way_num]),
        .readaddress(lanestate_readlane[way_num]),
        .readdata({lanestate_readdata[1][way_num], lanestate_readdata[0][way_num]}),

        .write(lanestate_write[way_num]),
        .writeaddress(lanestate_writelane),
        .writedata(lanestate_writedata)
    );

    for(byte_offset = 0; byte_offset < 32; byte_offset = byte_offset + 8) begin : storage_generate_for
        mem_1w1r #(
            .ELEMENTS_W(LANES_W+OFFSET_W),
            .WIDTH(8)
        ) datastorage (
            .clk(clk),

            .read(storage_read[way_num]),
            .readaddress({storage_readlane[way_num], storage_readoffset[way_num]}),
            .readdata(storage_readdata[way_num][byte_offset+7:byte_offset]),

            .write(storage_write[way_num] && storage_byteenable[byte_offset/8]),
            .writeaddress({storage_writelane, storage_writeoffset}),
            .writedata(storage_writedata[byte_offset+7:byte_offset])
        );
    end
end
endgenerate


// |------------------------------------------------|
// |                   LoadGen                      |
// |------------------------------------------------|

armleocpu_loadgen loadgen(
    .inwordOffset       (os_address_inword_offset),
    .loadType           (os_load_type),

    .LoadGenDataIn      (loadgen_datain),

    .LoadGenDataOut     (c_load_data),
    .LoadMissaligned    (loadgen_missaligned),
    .LoadUnknownType    (loadgen_unknowntype)
);

// |------------------------------------------------|
// |                 StoreGen                       |
// |------------------------------------------------|


armleocpu_storegen storegen(
    .inwordOffset           (os_address_inword_offset),
    .storegenType           (os_store_type),

    .storegenDataIn         (os_store_data),

    .storegenDataOut        (storegen_dataout),
    .storegenDataMask       (storegen_mask),
    .storegenMissAligned    (storegen_missaligned),
    .storegenUnknownType    (storegen_unknowntype)
);


// Page table walker instance
armleocpu_ptw ptw(
    .clk                    (clk),
    .rst_n                  (rst_n),

    .m_transaction          (ptw_m_transaction),
    .m_cmd                  (ptw_m_cmd),
    .m_address              (ptw_m_address),
    .m_transaction_done     (m_transaction_done),
    .m_transaction_response (m_transaction_response),
    .m_rdata                (m_rdata),
    
    .resolve_request        (ptw_resolve_request),
    /*verilator lint_off PINCONNECTEMPTY*/
    .resolve_ack            (),
    /*verilator lint_on PINCONNECTEMPTY*/
    .virtual_address        (ptw_resolve_vtag/*os_address_vtag*/),

    .resolve_done           (ptw_resolve_done),
    .resolve_pagefault      (ptw_pagefault),
    .resolve_accessfault    (ptw_accessfault),

    .resolve_access_bits    (ptw_resolve_access_bits),
    .resolve_physical_address(ptw_resolve_phystag),

    .satp_mode              (csr_satp_mode_r),
    .satp_ppn               (csr_satp_ppn_r)
);

armleocpu_tlb #(TLB_ENTRIES_W, TLB_WAYS_W) tlb(
    .rst_n                  (rst_n),
    .clk                    (clk),
    
    .command                (tlb_command),

    // read port
    .virtual_address        (tlb_resolve_virtual_address),
    .hit                    (tlb_hit),
    .accesstag_r            (tlb_read_accesstag),
    .phys_r                 (tlb_read_ptag),
    
    // write for for entry virt
    .virtual_address_w      (tlb_write_vtag),
    .accesstag_w            (tlb_write_accesstag),
    .phys_w                 (tlb_write_ptag),

    .invalidate_set_index   (tlb_invalidate_set_index)
);

armleocpu_cache_pagefault pagefault_generator(
    .csr_satp_mode_r            (csr_satp_mode_r),

    .csr_mcurrent_privilege  (csr_mcurrent_privilege),
    .csr_mstatus_mprv        (csr_mstatus_mprv),
    .csr_mstatus_mxr         (csr_mstatus_mxr),
    .csr_mstatus_sum         (csr_mstatus_sum),
    .csr_mstatus_mpp         (csr_mstatus_mpp),

    .os_cmd                     (os_cmd),
    .tlb_read_accesstag         (tlb_read_accesstag),

    .pagefault                  (pagefault)
    `ifdef DEBUG_PAGEFAULT
    , .reason(pagefault_reason)
    `endif
);



// |------------------------------------------------|
// |         Output stage data multiplexer          |
// |------------------------------------------------|
always @* begin : output_stage_mux
    integer way_idx;
    os_cache_hit = 1'b0;
    os_readdata = 32'h0;
    os_cache_hit_way = {WAYS_W{1'b0}};
    for(way_idx = WAYS-1; way_idx >= 0; way_idx = way_idx - 1) begin
        way_hit[way_idx] = os_valid_per_way[way_idx] && ((ptag_readdata[way_idx]) == ptag);
        if(way_hit[way_idx]) begin
            /*verilator lint_off WIDTH*/
            os_cache_hit_way = way_idx;
            /*verilator lint_on WIDTH*/
            os_readdata = storage_readdata[way_idx];
            os_cache_hit = 1'b1;
        end
    end
end

// unknowntype, missaligned multiplexer
always @* begin
    if(os_cmd == `CACHE_CMD_LOAD) begin
        unknowntype = loadgen_unknowntype;
        missaligned = loadgen_missaligned;
    end else begin
        unknowntype = storegen_unknowntype;
        missaligned = storegen_missaligned;
    end
end

reg [31:0] flush_way_idx;

always @* begin : flush_all_dirty_comb
    flush_all_any_lane_dirty = 1'b0;
    flush_all_dirty_lane_way = {WAYS_W{1'b0}};
    
    for(flush_way_idx = WAYS-1; !flush_way_idx[31]; flush_way_idx = flush_way_idx - 1) begin
        if({os_valid_per_way[flush_way_idx], os_dirty_per_way[flush_way_idx]} == 2'b11) begin
            flush_all_any_lane_dirty = 1'b1;
            /*verilator lint_off WIDTH*/
            flush_all_dirty_lane_way = flush_way_idx;
            /*verilator lint_on WIDTH*/
        end
    end
end

assign ptag = vm_enabled ? tlb_read_ptag : {2'b00, os_address_vtag};

always @* begin
    if(loadgen_datain_sel == 0)
        loadgen_datain = os_readdata;
    else
        loadgen_datain = m_rdata;
end


always @* begin : cache_comb
    integer i;

    tlb_command = `TLB_CMD_NONE;
    stall = 1;
    c_response = `CACHE_RESPONSE_IDLE;

    m_transaction = 0;
    m_cmd = `ARMLEOBUS_CMD_NONE;
    m_address = {ptag, os_address_lane, os_address_offset, 2'b00};
    m_burstcount = 0;
    m_wdata = storegen_dataout;
    m_wbyte_enable = storegen_mask;

    for(i = 0; i < WAYS; i = i + 1) begin
        ptag_read[i] = 1'b0;
        ptag_readlane[i] = c_address_lane;
        ptag_write[i] = 1'b0;

        lanestate_read[i] = 1'b0;
        lanestate_readlane[i] = c_address_lane;
        lanestate_write[i] = 1'b0;

        storage_read[i] = 1'b0;
        storage_readlane[i] = {LANES_W{1'b0}};
        storage_readoffset[i] = {OFFSET_W{1'b0}};
        storage_write[i] = 1'b0;
    end
    storage_writedata = storegen_dataout;
    storage_writelane = os_address_lane;
    storage_writeoffset = os_address_offset;
    storage_byteenable = storegen_mask;

    lanestate_writelane = {LANES_W{1'b0}};
    lanestate_writedata = 2'b11; // valid and dirty

    ptag_writedata = ptag;
    ptag_writelane = os_address_lane;
    ptw_resolve_request = 1'b0;
    ptw_resolve_vtag = os_address_vtag;
    loadgen_datain_sel = 0;
    
    tlb_resolve_virtual_address = c_address_vtag;
    tlb_write_vtag = os_address_vtag;
    tlb_write_accesstag = ptw_resolve_access_bits;
    tlb_write_ptag = ptw_resolve_phystag;

    if(tlb_invalidate_set_index == TLB_ENTRIES-1) begin
        tlb_invalidate_done = 1'b1;
    end else begin
        tlb_invalidate_done = 1'b0;
    end
    // used by state reset
    if(reset_lane_counter == LANES-1) begin
        reset_valid_reset_done = 1'b1;
    end else begin
        reset_valid_reset_done = 1'b0;
    end

    case(state)
        STATE_RESET: begin
            
            
            for(i = 0; i < WAYS; i = i + 1)
                lanestate_write[i] = 1'b1;
            lanestate_writedata = 2'b00;
            lanestate_writelane = reset_lane_counter;

            tlb_command = `TLB_CMD_INVALIDATE;
            
            c_response = `CACHE_RESPONSE_WAIT;
            stall = 1;
        end
        STATE_ACTIVE: begin
            
            stall = 0;
            if(os_active) begin
                if(os_error) begin
                    // Returned from refill or flush and error happened
                    stall = 0;
                    if(os_error_type == `CACHE_ERROR_ACCESSFAULT)
                        c_response = `CACHE_RESPONSE_ACCESSFAULT;
                    else if(os_error_type == `CACHE_ERROR_PAGEFAULT)
                        c_response = `CACHE_RESPONSE_PAGEFAULT;
                end else if(unknowntype) begin
                    c_response = `CACHE_RESPONSE_UNKNOWNTYPE;
                end else if(missaligned) begin
                    c_response = `CACHE_RESPONSE_MISSALIGNED;
                end else if(vm_enabled && !tlb_hit) begin
                    // TLB Miss
                    stall = 1;
                    c_response = `CACHE_RESPONSE_WAIT;
                end else if(vm_enabled && pagefault) begin
                    // pagefault
                    c_response = `CACHE_RESPONSE_PAGEFAULT;
                end else begin
                    
                    // TLB Hit
                    if(ptag[19] && BYPASS_ENABLED) begin
                        // bypass
                        loadgen_datain_sel = 1;
                        //m_wdata = storegen_dataout;
                        //m_wbyte_enable = storegen_mask;
                        if((os_cmd == `CACHE_CMD_LOAD) || (os_cmd == `CACHE_CMD_EXECUTE)) begin
                            m_cmd = `ARMLEOBUS_CMD_READ;
                        end else if(os_cmd == `CACHE_CMD_STORE) begin
                            m_cmd = `ARMLEOBUS_CMD_WRITE;
                        end
                        m_transaction = 1'b1;
                        c_response = `CACHE_RESPONSE_WAIT;
                        stall = 1'b1;
                        if(m_transaction_done) begin
                            stall = 1'b0;
                            if(m_transaction_response == `ARMLEOBUS_RESPONSE_SUCCESS)
                                c_response = `CACHE_RESPONSE_DONE;
                            else
                                c_response = `CACHE_RESPONSE_ACCESSFAULT;
                        end
                    end else begin
                        // cache access (no bypass)
                        loadgen_datain_sel = 0;
                        storage_byteenable = storegen_mask;
                        storage_writedata = storegen_dataout;
                        lanestate_writedata = 2'b11;
                        if(os_cache_hit) begin
                            // Cache hit
                            c_response = `CACHE_RESPONSE_DONE;
                            if(os_cmd == `CACHE_CMD_STORE) begin
                                lanestate_writelane = os_address_lane;
                                storage_write[os_cache_hit_way] = 1'b1;
                                lanestate_write[os_cache_hit_way] = 1'b1;
                                c_response = `CACHE_RESPONSE_DONE;
                            end
                        end else begin
                            // Cache miss
                            stall = 1;
                            c_response = `CACHE_RESPONSE_WAIT;
                        end // cache miss end
                    end // bypass/cache end
                end // no error end
            end // os active end
        end
        STATE_REFILL: begin
            m_cmd = `ARMLEOBUS_CMD_READ;
            m_transaction = 1'b1;
            m_address = {ptag, os_address_lane, os_word_counter, 2'b00};
            m_burstcount = WORDS_IN_LANE-1;
            storage_writelane = os_address_lane;
            storage_writeoffset = os_word_counter;
            storage_writedata = m_rdata;
            storage_byteenable = 4'hF;
            lanestate_writelane = os_address_lane;
            lanestate_writedata = 2'b01;
            
            ptag_writelane = os_address_lane;
            ptag_writedata = ptag;

            if(m_transaction_done) begin
                if(m_transaction_response != `ARMLEOBUS_RESPONSE_SUCCESS) begin
                    
                end else begin
                    storage_write[victim_way] = 1'b1;
                    
                    if(os_word_counter == WORDS_IN_LANE - 1) begin
                        lanestate_write[victim_way] = 1'b1;
                        lanestate_read[victim_way] = 1'b1;
                        storage_read[victim_way] = 1'b1;
                        storage_readlane[victim_way] = os_address_lane;
                        storage_readoffset[victim_way] = os_address_offset;
                        ptag_write[victim_way] = 1'b1;
                        ptag_read[victim_way] = 1'b1;
                    end
                end
            end
            stall = 1;
            c_response = `CACHE_RESPONSE_WAIT;
        end
        STATE_FLUSH: begin
            m_cmd = flush_initial_done ? `ARMLEOBUS_CMD_WRITE : `ARMLEOBUS_CMD_NONE;
            m_address = {ptag_readdata[flush_current_way], os_address_lane, os_word_counter, 2'b00};
            m_burstcount = WORDS_IN_LANE-1;

            m_wdata = storage_readdata[flush_current_way];
            m_wbyte_enable = 4'hF;

            storage_readlane[flush_current_way] = os_address_lane;
            storage_readoffset[flush_current_way] = os_word_counter + 1;
            
            ptag_readlane[flush_current_way] = os_address_lane;

            if(!flush_initial_done) begin
                storage_readoffset[flush_current_way] = 0;
                storage_read[flush_current_way] = 1'b1;
                ptag_read[flush_current_way] = 1'b1;
            end else begin
                m_transaction = 1'b1;
                if(m_transaction_done) begin
                    if(m_transaction_response == `ARMLEOBUS_RESPONSE_SUCCESS) begin
                        if(os_word_counter == WORDS_IN_LANE-1) begin
                            // sync: change to return state
                        end else begin
                            storage_read[flush_current_way] = 1'b1;
                            //storage_readoffset[flush_current_way] = os_word_counter + 1;
                        end
                    end
                    // transaction not successfult -> no need to do anything
                    // because this is bug
                end
            end
            stall = 1;
            c_response = `CACHE_RESPONSE_WAIT;
        end
        STATE_PTW: begin
            m_transaction = ptw_m_transaction;
            m_cmd = ptw_m_cmd;
            m_address = ptw_m_address;
            m_burstcount = 0; // one word = 0

            stall = 1;
            c_response = `CACHE_RESPONSE_WAIT;

            

            ptw_resolve_request = 1'b1;
            if(ptw_resolve_done) begin
                if(ptw_accessfault) begin
                    // sync will handle this
                end else if(ptw_pagefault) begin
                    // sync will handle this
                end else begin
                    tlb_command = `TLB_CMD_WRITE;
                end
            end
        end
        STATE_FLUSH_ALL: begin
            lanestate_writelane = flush_all_current_lane[LANES_W-1:0];
            lanestate_writedata = 2'b01;
            for(i = 0; i < WAYS; i = i + 1) begin
                lanestate_readlane[i] = flush_all_current_lane[LANES_W-1:0];
            end
            case(substate)
                SUBSTATE_FLUSH_ALL_INITIAL: begin
                end
                SUBSTATE_FLUSH_ALL_TLB_INVALIDATE: begin
                    tlb_command = `TLB_CMD_INVALIDATE;
                end
                SUBSTATE_FLUSH_ALL_FETCH: begin
                    if(!flush_all_done) begin
                        for(i = 0; i < WAYS; i = i + 1) begin
                            lanestate_read[i] = 1'b1;
                        end
                    end else begin
                        c_response = `CACHE_RESPONSE_DONE;
                    end
                end
                SUBSTATE_FLUSH_ALL_DECIDE: begin
                    if(flush_all_any_lane_dirty) begin
                        lanestate_write[flush_all_dirty_lane_way] = 1'b1;
                    end
                end
            endcase
            //tlb_command = `TLB_CMD_INVALIDATE;
            stall = 1;
        end
        /*verilator coverage_off*/
        default: begin
            c_response = `CACHE_RESPONSE_WAIT;
            stall = 1;
        end
        /*verilator coverage_on*/
    endcase
    if(!stall) begin
        if(access_request) begin
            for(i = 0; i < WAYS; i = i + 1) begin
                storage_read[i]         = 1'b1;
                storage_readlane[i]     = c_address_lane;
                storage_readoffset[i]   = c_address_offset;
                storage_byteenable      = storegen_mask;
                lanestate_read[i]       = 1'b1;
                lanestate_readlane [i]  = c_address_lane;

                ptag_read[i]            = 1'b1;
                ptag_readlane[i]        = c_address_lane;
            end
            tlb_command = `TLB_CMD_RESOLVE;
        end
    end
end

always @(posedge clk) begin
    if(!rst_n) begin
        state <= STATE_RESET;
        reset_lane_counter <= {LANES_W{1'b0}};
        tlb_invalidate_set_index <= {TLB_ENTRIES_W{1'b0}};
    end else begin
        case(state)
            STATE_RESET: begin
                os_active <= 1'b0;
                os_address_lane <= {LANES_W{1'b0}};
                os_word_counter <= {OFFSET_W{1'b0}};
                
                victim_way <= {WAYS_W{1'b0}};
                os_error <= 1'b0;
                if(!reset_valid_reset_done)
                    reset_lane_counter <= reset_lane_counter + 1;
                if(!tlb_invalidate_done)
                    tlb_invalidate_set_index <= tlb_invalidate_set_index + 1;

                if(tlb_invalidate_done && reset_valid_reset_done) begin
                    state <= STATE_ACTIVE;
                    reset_lane_counter <= 0;
                    tlb_invalidate_set_index <= 0;
                    `ifdef DEBUG_CACHE
                        $display("[%m][%d] Reset done", $time);
                    `endif
                    csr_satp_mode_r <= csr_satp_mode;
                    csr_satp_ppn_r <= csr_satp_ppn;
                end
            end
            STATE_ACTIVE: begin
                if(os_active) begin
                    if(os_error) begin
                        // Returned from refill/flush with error
                        // Empty because no need to do anything
                        os_active <= 0;
                        os_error <= 0;
                        `ifdef DEBUG_CACHE
                        if(os_error_type == `CACHE_ERROR_ACCESSFAULT)
                            $display("[%m][%d][Output Stage] Accessfault Error from prev cycle", $time);
                        else
                            $display("[%m][%d][Output Stage] Pagefault Error from prev cycle", $time);
                        
                        `endif
                    end else if(unknowntype) begin
                        `ifdef DEBUG_CACHE
                        $display("[%m][%d][Output Stage] %s, unknowntype", $time, os_cmd_ascii);
                        `endif
                        os_active <= 0;
                    end else if(missaligned) begin
                        `ifdef DEBUG_CACHE
                        $display("[%m][%d][Output Stage] %s, missaligned", $time, os_cmd_ascii);
                        `endif
                        os_active <= 0;
                    end else if(vm_enabled && !tlb_hit) begin
                        // TLB Miss
                        `ifdef DEBUG_CACHE
                        $display("[%m][%d][Output Stage] TLB Miss", $time);
                        `endif
                        state <= STATE_PTW;
                    end else if(vm_enabled && pagefault) begin
                        // pagefault
                        `ifdef DEBUG_CACHE
                        $display("[%m][%d][Output Stage] %s, tlb hit, pagefault", $time, os_cmd_ascii);
                        `ifdef DEBUG_PAGEFAULT
                            $display("[%m][%d][pagefault] pagefault_reason = %s", $time, pagefault_reason);
                        `endif
                        `endif
                        os_active <= 0;
                    end else begin
                        // tlb hit
                        if(ptag[19] && BYPASS_ENABLED) begin
                            // bypass
                            if(m_transaction_done) begin
                                if(m_transaction_response == `ARMLEOBUS_RESPONSE_SUCCESS) begin
                                    `ifdef DEBUG_CACHE
                                        if(m_cmd == `ARMLEOBUS_CMD_READ) begin
                                            $display("[%m][%d][Output Stage] %s, bypass done m_address = 0x%X, m_rdata = 0x%X, load_type = %s",
                                                    $time, os_cmd_ascii, m_address, m_rdata, os_load_type_ascii);
                                        end else begin
                                            $display("[%m][%d][Output Stage] %s, bypass done m_address = 0x%X, m_wdata = 0x%X, os_store_data=0x%X, store_type = %s",
                                                    $time, os_cmd_ascii, m_address, m_wdata, os_store_data, os_store_type_ascii);
                                        end
                                    `endif
                                end
                                // Unsuccessful handled in async
                                os_active <= 1'b0;
                            end
                        end else begin
                            // Cached access
                            if(os_cache_hit) begin
                                // Cache hit
                                os_active <= 1'b0;
                                // TODO: log
                                `ifdef DEBUG_CACHE
                                    $display("[%m][%d][Output Stage] %s, Cache hit", $time, os_cmd_ascii);
                                `endif
                            end else begin // no cache hit
                                // Cache miss
                                if(os_victim_valid && os_victim_dirty) begin
                                    `ifdef DEBUG_CACHE
                                        $display("[%m][%d][Output Stage] Cache miss, victim dirty", $time);
                                    `endif
                                    state <= STATE_FLUSH;
                                    flush_initial_done <= 0;
                                    flush_current_way <= victim_way;
                                    return_state <= STATE_REFILL;
                                end else begin
                                    `ifdef DEBUG_CACHE
                                        $display("[%m][%d][Output Stage] Cache miss, victim clean", $time);
                                    `endif
                                    state <= STATE_REFILL;
                                end
                            end // cache hit/miss
                        end // tlb_ptag_read[19]
                    end
                end // os_active
            end // CASE
            STATE_REFILL: begin
                if(m_transaction_done) begin
                    if(m_transaction_response != `ARMLEOBUS_RESPONSE_SUCCESS) begin
                        `ifdef DEBUG_CACHE
                            $display("[%m][%d][Refill] Memory responded with failed transaction", $time);
                        `endif
                        state <= STATE_ACTIVE;
                        os_error <= 1;
                        os_error_type <= `CACHE_ERROR_ACCESSFAULT;
                        os_word_counter <= 0;
                    end else begin
                        
                        os_word_counter <= os_word_counter + 1;
                        if(os_word_counter == WORDS_IN_LANE - 1) begin
                            `ifdef DEBUG_CACHE
                                $display("[%m][%d][Refill] Refill done os_address_vtag = 0x%X, ptag = 0x%X, os_address_lane = 0x%X",
                                                $time, os_address_vtag, ptag, os_address_lane);
                            `endif
                            os_word_counter <= 0;
                            state <= STATE_ACTIVE;
                            victim_way <= victim_way + 1'b1;
                        end
                    end
                end
            end
            STATE_FLUSH: begin
                // for each word in storage write to ptag for that way-lane
                if(!flush_initial_done) begin
                    `ifdef DEBUG_CACHE
                        $display("[%m][%d][Flush] Flushing way=0x%X, lane=0x%X",
                                  $time, flush_current_way, os_address_lane);
                    `endif
                    // async: fetch first word from storage, fetch ptag
                    // sync: zero word counter
                    os_word_counter <= 0;
                    flush_initial_done <= 1'b1;
                end else begin
                    if(m_transaction_done) begin
                        os_word_counter <= os_word_counter + 1;
                        if(m_transaction_response == `ARMLEOBUS_RESPONSE_SUCCESS) begin
                            os_word_counter <= os_word_counter + 1;
                            if(os_word_counter == WORDS_IN_LANE - 1) begin
                                `ifdef DEBUG_CACHE
                                    $display("[%m][%d][Flush] Flush done ptag = 0x%X, way = 0x%X, ptag_readdata[flush_current_way] = 0x%X, os_address_lane = 0x%X",
                                                    $time, ptag, flush_current_way, ptag_readdata[flush_current_way], os_address_lane);
                                `endif
                                os_word_counter <= 0;
                                flush_initial_done <= 0;
                                state <= return_state;
                            end
                        end
                        /*verilator coverage_off*/
                            else begin
                            `ifdef DEBUG_CACHE

                                $display("[%m][%d][Flush] [BUG] Memory responded with failed transaction", $time);
                            `endif
                            //state <= STATE_ACTIVE;
                            //os_error <= 1;
                            //os_error_type <= `CACHE_ERROR_ACCESSFAULT;
                            //os_word_counter <= 0;
                            
                        end
                        /*verilator coverage_on*/
                    end
                end
                //
            end
            STATE_FLUSH_ALL: begin
                // Read all ways for lane os_address_lane + 1;
                // if no ways dirty -> next lane
                //      if last lane checked -> go to idle
                // if any way dirty -> go to state flush
                // no bus error is possible because all cached addresses exist
                // no other erros is possible


                // os_active <= 1'b1;
                // os_error <= 1'b1;
                return_state <= STATE_FLUSH_ALL;
                os_word_counter <= 0;
                flush_initial_done <= 0;
                case(substate)
                    SUBSTATE_FLUSH_ALL_INITIAL: begin
                        csr_satp_mode_r <= csr_satp_mode;
                        csr_satp_ppn_r  <= csr_satp_ppn;
                        flush_all_current_lane <= 0;
                        tlb_invalidate_set_index <= 0;
                        substate <= SUBSTATE_FLUSH_ALL_TLB_INVALIDATE;
                        os_error <= 1'b0;
                        `ifdef DEBUG_CACHE
                            $display("[%m][%d][Flush_all] Flushing all memory",
                                                        $time);
                        `endif
                        // readlane
                    end
                    SUBSTATE_FLUSH_ALL_TLB_INVALIDATE: begin
                        tlb_invalidate_set_index <= tlb_invalidate_set_index + 1;
                        if(tlb_invalidate_done) begin
                            substate <= SUBSTATE_FLUSH_ALL_FETCH;
                            tlb_invalidate_set_index <= 0;
                        end
                    end
                    SUBSTATE_FLUSH_ALL_FETCH: begin
                        // fetch all ways, flush_all_current_lane
                        substate <= SUBSTATE_FLUSH_ALL_DECIDE;
                        if(flush_all_done) begin
                            flush_all_current_lane <= 0;
                            state <= STATE_ACTIVE;
                            substate <= SUBSTATE_FLUSH_ALL_INITIAL;
                            `ifdef DEBUG_CACHE
                                $display("[%m][%d][Flush_all] Flush all done", $time);
                            `endif
                        end
                        `ifdef DEBUG_CACHE
                        /*verilator coverage_off*/
                        if(os_error)
                            $display("[%m][%d][Flush_all] Memory accessfault, !BUG!", $time);
                        /*verilator coverage_on*/
                        `endif
                    end
                    SUBSTATE_FLUSH_ALL_DECIDE: begin
                        substate <= SUBSTATE_FLUSH_ALL_FETCH;
                        flush_current_way <= flush_all_dirty_lane_way;
                        os_address_lane <= flush_all_current_lane[LANES_W-1:0];
                        if(flush_all_any_lane_dirty) begin
                            state <= STATE_FLUSH;
                        end else begin
                            flush_all_current_lane <= flush_all_current_lane + 1;
                        end
                    end
                endcase // substate
            end // case flush all
            STATE_PTW: begin
                if(ptw_resolve_done) begin
                    state <= STATE_ACTIVE;
                    if(ptw_accessfault) begin
                        os_error_type <= `CACHE_ERROR_ACCESSFAULT;
                        os_error <= 1'b1;
                        `ifdef DEBUG_CACHE
                            $display("[%m][%d][PTW] PTW Accessfault, os_address_vtag = 0x%X", $time, os_address_vtag);
                        `endif
                    end else if(ptw_pagefault) begin
                        os_error_type <= `CACHE_ERROR_PAGEFAULT;
                        os_error <= 1'b1;
                        `ifdef DEBUG_CACHE
                            $display("[%m][%d][PTW] PTW Pagefault, os_address_vtag = 0x%X", $time, os_address_vtag);
                        `endif
                    end else begin
                        `ifdef DEBUG_CACHE
                            $display("[%m][%d][PTW] PTW Resolve done, os_address_vtag = 0x%X, ptw_resolve_access_bits = 0x%X, ptw_resolve_phystag = 0x%X", $time, os_address_vtag, ptw_resolve_access_bits, ptw_resolve_phystag);
                        `endif
                        os_error <= 1'b0;
                        //tlb_command = `TLB_CMD_WRITE;
                    end
                end
            end
            /*verilator coverage_off*/ 
            default: begin
                `ifdef DEBUG_CACHE
                    $display("[%m][%d] Unknown state", $time);
                `endif
                state <= STATE_RESET;
            end
            /*verilator coverage_on*/ 
        endcase
        if(!stall) begin
            if(access_request) begin
                `ifdef DEBUG_CACHE
                    $display("[%m][%d] %s access request c_address = 0x%X, c_load_type = 0x%X, c_store_type = 0x%X, c_store_data = 0x%X",
                             $time, c_cmd_ascii, c_address, c_load_type, c_store_type, c_store_data);
                `endif
                os_active                   <= 1'b1;

                os_address_vtag             <= c_address_vtag;
                os_address_lane             <= c_address_lane;
                os_address_offset           <= c_address_offset;
                os_address_inword_offset    <= c_address_inword_offset;

                os_cmd                      <= c_cmd;
                os_load_type                <= c_load_type;
                os_store_type               <= c_store_type;
                os_store_data               <= c_store_data;
            end
            if(c_cmd == `CACHE_CMD_FLUSH_ALL) begin
                `ifdef DEBUG_CACHE
                    $display("[%m][%d] IDLE -> FLUSH_ALL", $time);
                `endif
                state <= STATE_FLUSH_ALL;
                os_word_counter <= 0;
                flush_all_current_lane <= 0;
                substate <= SUBSTATE_FLUSH_ALL_INITIAL;
            end
        end
    end
end


// Debug outputs
`ifdef DEBUG_CACHE
/*verilator coverage_off*/
reg [(9*8)-1:0] state_ascii;
always @* begin case(state)
    STATE_ACTIVE:       state_ascii = "ACTIVE";
    STATE_FLUSH:        state_ascii = "FLUSH";
    STATE_REFILL:       state_ascii = "REFILL";
    STATE_FLUSH_ALL:    state_ascii = "FLUSH_ALL";
    STATE_PTW:          state_ascii = "PTW";
    STATE_RESET:        state_ascii = "RESET";
    default:            state_ascii = "?????????";
    endcase
end

reg [(9*8)-1:0] return_state_ascii;
always @* begin case(return_state)
    STATE_ACTIVE:         return_state_ascii = "IDLE";
    STATE_FLUSH:        return_state_ascii = "FLUSH";
    STATE_REFILL:       return_state_ascii = "REFILL";
    STATE_FLUSH_ALL:    return_state_ascii = "FLUSH_ALL";
    STATE_PTW:          return_state_ascii = "PTW";
    default:            return_state_ascii = "?????????";
    endcase
end

reg [(18*8)-1:0] substate_ascii;
always @* begin
    case(state)
    STATE_FLUSH_ALL:
        case(substate)
            SUBSTATE_FLUSH_ALL_INITIAL:         substate_ascii = "INITIAL";
            SUBSTATE_FLUSH_ALL_FETCH:           substate_ascii = "FETCH";
            SUBSTATE_FLUSH_ALL_DECIDE:          substate_ascii = "DECIDE";
            SUBSTATE_FLUSH_ALL_TLB_INVALIDATE:  substate_ascii = "TLB_INVALIDATE";
            default:                            substate_ascii = "??????????????";
        endcase
    default:
        substate_ascii = "NONE";
    endcase
end
/*verilator coverage_on*/
`endif

endmodule
