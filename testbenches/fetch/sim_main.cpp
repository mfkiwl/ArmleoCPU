#include <verilated.h>
#include <verilated_vcd_c.h>
#include <Vcorevx_fetch.h>
#include <iostream>

vluint64_t simulation_time = 0;
VerilatedVcdC	*m_trace;
bool trace = 1;
Vcorevx_fetch* corevx_fetch;

uint32_t testnum;

using namespace std;

const int CACHE_CMD_NONE = 0;
const int CACHE_CMD_EXECUTE = 1;
const int CACHE_CMD_LOAD = 2;
const int CACHE_CMD_STORE = 3;
const int CACHE_CMD_FLUSH_ALL = 4;

const int CACHE_RESPONSE_IDLE = 0;
const int CACHE_RESPONSE_WAIT = 1;
const int CACHE_RESPONSE_DONE = 2;
const int CACHE_RESPONSE_ACCESSFAULT = 3;
const int CACHE_RESPONSE_PAGEFAULT = 4;
const int CACHE_RESPONSE_MISSALIGNED = 5;
const int CACHE_RESPONSE_UNKNOWNTYPE = 6;

const uint32_t INSTR_NOP = 0b0010011;

double sc_time_stamp() {
    return simulation_time;  // Note does conversion to real, to match SystemC
}
void dump_step() {
    simulation_time++;
    if(trace) m_trace->dump(simulation_time);
}
void update() {
    corevx_fetch->eval();
    dump_step();
}

void posedge() {
    corevx_fetch->clk = 1;
    update();
    update();
}

void till_user_update() {
    corevx_fetch->clk = 0;
    update();
}
void after_user_update() {
    update();
}

void dummy_cycle() {
    after_user_update();

    posedge();
    till_user_update();
}

void check(bool match, string msg) {
    
    if(!match) {
        cout << "testnum: " << testnum << endl;
        cout << msg << endl;
        throw runtime_error(msg);
    }
}

void check_instr_nop() {
    check(corevx_fetch->f2e_instr == INSTR_NOP, "unexpected instruction instead of NOP");
};

int main(int argc, char** argv, char** env) {
    cout << "Fetch Test started" << endl;
    // This is a more complicated example, please also see the simpler examples/make_hello_c.

    // Prevent unused variable warnings
    if (0 && argc && argv && env) {}

    // Set debug level, 0 is off, 9 is highest presently used
    // May be overridden by commandArgs
    Verilated::debug(0);

    // Randomization reset policy
    // May be overridden by commandArgs
    Verilated::randReset(2);

    // Verilator must compute traced signals
    Verilated::traceEverOn(true);

    // Pass arguments so Verilated code can see them, e.g. $value$plusargs
    // This needs to be called before you create any model
    Verilated::commandArgs(argc, argv);

    // Create logs/ directory in case we have traces to put under it
    Verilated::mkdir("logs");

    // Construct the Verilated model, from Vcorevx_fetch.h generated from Verilating "corevx_fetch.v"
    corevx_fetch = new Vcorevx_fetch;  // Or use a const unique_ptr, or the VL_UNIQUE_PTR wrapper
    m_trace = new VerilatedVcdC;
    corevx_fetch->trace(m_trace, 99);
    m_trace->open("vcd_dump.vcd");
    try {
    corevx_fetch->mtvec = 0x2000;
    corevx_fetch->rst_n = 0;
    corevx_fetch->irq_timer = 0;
    corevx_fetch->irq_exti = 0;

    dummy_cycle();
    corevx_fetch->rst_n = 1;
    corevx_fetch->c_reset_done = 0;
    corevx_fetch->e2f_ready = 0;
    dummy_cycle();
    dummy_cycle();

    cout << "pretending to fetch instructions" << endl;
    testnum = 0;
    corevx_fetch->rst_n = 1;
    corevx_fetch->c_reset_done = 1;
    corevx_fetch->c_response = CACHE_RESPONSE_IDLE;
    corevx_fetch->c_load_data = 0;
    corevx_fetch->e2f_ready = 1;
    corevx_fetch->e2f_exc_start = 0;
    corevx_fetch->e2f_flush = 0;
    corevx_fetch->e2f_branchtaken = 0;
    corevx_fetch->e2f_branchtarget = 0;
    corevx_fetch->eval();
    check(corevx_fetch->c_cmd == CACHE_CMD_EXECUTE, "First cycle is not execute");
    check(corevx_fetch->c_address == 0, "First fetch is not from reset vector");
    check(corevx_fetch->f2e_exc_start == 0, "Exception that should not happen");
    check_instr_nop();
    
    testnum = 1;
    dummy_cycle();
    corevx_fetch->c_response = CACHE_RESPONSE_WAIT;
    corevx_fetch->c_load_data = 0;
    corevx_fetch->e2f_ready = 1;
    corevx_fetch->eval();
    check_instr_nop();
    check(corevx_fetch->f2e_exc_start == 0, "Exception that should not happen");
    dummy_cycle();

    testnum = 2;
    corevx_fetch->c_response = CACHE_RESPONSE_DONE;
    corevx_fetch->c_load_data = 0xFF00FF00;
    corevx_fetch->e2f_ready = 1;
    corevx_fetch->eval();
    check(corevx_fetch->f2e_pc == 0, "unexpected pc");
    check(corevx_fetch->f2e_instr == 0xFF00FF00, "unexpected instr");
    check(corevx_fetch->f2e_exc_start == 0, "Exception that should not happen");
    check(corevx_fetch->c_cmd == CACHE_CMD_EXECUTE, "next fetch not happening");
    check(corevx_fetch->c_address == 0x4, "next fetch pc incorrect");
    dummy_cycle();

    cout << "Accessfault test";
    testnum = 3;
    corevx_fetch->c_response = CACHE_RESPONSE_ACCESSFAULT;
    corevx_fetch->eval();
    check_instr_nop();
    check(corevx_fetch->f2e_exc_start == 1, "Expected exception not happened");
    check(corevx_fetch->f2e_cause == 1, "Expected exception incorrect cause");
    check(corevx_fetch->f2e_interrupt == 0, "Expected exception not happened");
    //check_instr_nop();

    cout << "Fetch Tests done" << endl;

    } catch(exception e) {
        cout << e.what();
        dummy_cycle();
        dummy_cycle();
        
    }
    corevx_fetch->final();
    if (m_trace) {
        m_trace->close();
        m_trace = NULL;
    }
#if VM_COVERAGE
    Verilated::mkdir("logs");
    VerilatedCov::write("logs/coverage.dat");
#endif

    // Destroy model
    delete corevx_fetch; corevx_fetch = NULL;

    // Fin
    exit(0);
}