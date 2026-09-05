`timescale 1ns/1ps
module tb_teach_soc;
 reg clk=0,resetn=0;
 always #5 clk=~clk;
 wire [6:0] digital_num0,digital_num1;
 wire [7:0] digital_cs,led;
 // Intentionally instantiate the original supplied top without editing its ports.
 teach_soc_top dut(.clk(clk),.resetn(resetn),.mid_btn_key(1'b0),
  .left_btn_key(1'b0),.right_btn_key(1'b0),.up_btn_key(1'b0),
  .down_btn_key(1'b0),.switch(8'hff),.digital_num0(digital_num0),
  .digital_num1(digital_num1),.digital_cs(digital_cs),.led(led));
 integer golden=0,rows=0,cycles=0,got,flag,epoch=0;
 integer bus_stores=0,retired_stores=0,tail_cycles=0,max_cycles=200000;
 reg [31:0] ref_pc,ref_data,ref_rd,tail_pc=32'hbfc00104,tail_value;
 reg [31:0] store_addr[0:65535],store_data[0:65535];
 reg [3:0] store_strobe[0:65535];
 reg completed=0,reset_cancel_checked=0;
 integer trace_file;

 task reopen_golden;
 begin
  if(golden) $fclose(golden);
  golden=$fopen("golden_trace.txt","r");
  if(!golden) $fatal(1,"FAIL TEACH_SOC missing golden trace");
  rows=0;cycles=0;bus_stores=0;retired_stores=0;completed=0;tail_cycles=0;
 end
 endtask

 initial begin
  if($test$plusargs("EARLY_TIMEOUT")) max_cycles=10;
  trace_file=$fopen("teach_retirements.csv","w");
  if(!trace_file) $fatal(1,"FAIL TEACH_SOC trace output open");
  $fdisplay(trace_file,"epoch,cycle,pc,instruction,write_enable,rd,value,store_strobe,store_address,store_value");
  reopen_golden();
  repeat(5) @(negedge clk);
  #1;resetn=1;
  // Cancel the first newly presented store before the memory rising edge.
  wait(dut.cpu_data_en && |dut.cpu_data_wen);
  #1;resetn=0;
  repeat(4) @(negedge clk);
  #1;
  if(bus_stores!=0 || led!==8'hff || dut.confreg.digital_num_v!==0)
   $fatal(1,"FAIL TEACH_SOC reset failed to cancel first store");
  reset_cancel_checked=1;epoch=1;reopen_golden();resetn=1;
 end

 // Actual SRAM/MMIO side effects occur here, half a cycle before CPU handshake.
 always @(posedge clk) begin
  if(!resetn) begin
   if(dut.cpu_inst_en!==0 || dut.cpu_data_en!==0 || dut.cpu_data_wen!==0 || dut.debug_wb_rf_wen!==0)
    $fatal(1,"FAIL TEACH_SOC bus/debug activity in reset");
  end else begin
   if(dut.cpu_inst_wen!==0) $fatal(1,"FAIL TEACH_SOC instruction write");
   if(dut.cpu_data_en && |dut.cpu_data_wen) begin
    if(completed || bus_stores>=65536) $fatal(1,"FAIL TEACH_SOC extra bus store");
    store_addr[bus_stores]=dut.cpu_data_addr;
    store_data[bus_stores]=dut.cpu_data_wdata;
    store_strobe[bus_stores]=dut.cpu_data_wen;
    bus_stores=bus_stores+1;
   end
  end
 end

 // Sample before the falling-edge CPU's nonblocking architectural updates.
 always @(negedge clk) if(resetn) begin
  cycles=cycles+1;
  if(dut.cpu.exception_valid) $fatal(1,"FAIL TEACH_SOC exception code=%0d epc=%h",dut.cpu.exception_code,dut.cpu.exception_epc);
  if(dut.cpu.trace_valid) begin
   // Original test_finish loops through addiu t0,t0,1; b; nop forever.
   // Golden stops after its first addiu. Verify the known tail independently.
   if(completed) begin
    if(dut.debug_wb_pc!==tail_pc) $fatal(1,"FAIL TEACH_SOC unexpected tail pc=%h",dut.debug_wb_pc);
    case(tail_pc)
     32'hbfc00100: begin
      tail_value=tail_value+1;
      if(dut.cpu.trace_instr!==32'h25080001 || dut.debug_wb_rf_wen!==4'hf ||
       dut.debug_wb_rf_wnum!==8 || dut.debug_wb_rf_wdata!==tail_value)
       $fatal(1,"FAIL TEACH_SOC unexpected tail register write");
      tail_pc=32'hbfc00104;
     end
     32'hbfc00104: begin
      if(dut.cpu.trace_instr!==32'h1000fffe || dut.debug_wb_rf_wen!==0)
       $fatal(1,"FAIL TEACH_SOC unexpected tail branch");
      tail_pc=32'hbfc00108;
     end
     32'hbfc00108: begin
      if(dut.cpu.trace_instr!==0 || dut.debug_wb_rf_wen!==0)
       $fatal(1,"FAIL TEACH_SOC unexpected tail delay slot");
      tail_pc=32'hbfc00100;
     end
     default: $fatal(1,"FAIL TEACH_SOC invalid tail state");
    endcase
   end
   $fdisplay(trace_file,"%0d,%0d,%08h,%08h,%0d,%0d,%08h,%01h,%08h,%08h",epoch,cycles,
    dut.debug_wb_pc,dut.cpu.trace_instr,|dut.debug_wb_rf_wen,dut.debug_wb_rf_wnum,
    dut.debug_wb_rf_wdata,dut.cpu.trace_mem_we,dut.cpu.trace_mem_addr,dut.cpu.trace_mem_wdata);
   if(|dut.cpu.trace_mem_we) begin
    if(retired_stores>=bus_stores ||
      {3'b0,dut.cpu.trace_mem_addr[28:0]}!==store_addr[retired_stores] ||
      dut.cpu.trace_mem_wdata!==store_data[retired_stores] ||
      dut.cpu.trace_mem_we!==store_strobe[retired_stores])
     $fatal(1,"FAIL TEACH_SOC store mismatch retirement=%0d bus=%0d",retired_stores,bus_stores);
    retired_stores=retired_stores+1;
   end
  end
  if(!completed && |dut.debug_wb_rf_wen && dut.debug_wb_rf_wnum!=0) begin
   got=$fscanf(golden,"%h %h %h %h",flag,ref_pc,ref_rd,ref_data);
   if(got!=4 || flag!=1 || dut.debug_wb_rf_wen!==4'hf ||
    dut.debug_wb_pc!==ref_pc || {27'b0,dut.debug_wb_rf_wnum}!==ref_rd || dut.debug_wb_rf_wdata!==ref_data)
    $fatal(1,"FAIL TEACH_SOC row=%0d fields=%0d actual=%h/%h/%h expected=%h/%h/%h",rows,got,
     dut.debug_wb_pc,dut.debug_wb_rf_wnum,dut.debug_wb_rf_wdata,ref_pc,ref_rd,ref_data);
   rows=rows+1;
  end
  if(!completed && dut.cpu.trace_valid && dut.debug_wb_pc==32'hbfc00100 && epoch==1) begin
   if(led!==8'h0f || dut.confreg.digital_num_v!==32'h13000013 || !reset_cancel_checked)
    $fatal(1,"FAIL TEACH_SOC final state led=%h display=%h",led,dut.confreg.digital_num_v);
   got=$fscanf(golden,"%h",flag);
   if(got!=-1) $fatal(1,"FAIL TEACH_SOC unconsumed or malformed golden tail fields=%0d",got);
   if(rows!=28970 || bus_stores!=retired_stores)
    $fatal(1,"FAIL TEACH_SOC incomplete rows=%0d stores=%0d/%0d",rows,retired_stores,bus_stores);
   tail_value=ref_data;completed=1;
  end
  if(completed) begin
   tail_cycles=tail_cycles+1;
   if(tail_cycles==32) begin
    $display("PASS TEACH_SOC rows=%0d cycles=%0d stores=%0d display=%h led=%h enabled_points=19 reset_cancel=1 checked_tail=32",
     rows,cycles,bus_stores,dut.confreg.digital_num_v,led);
    $fclose(golden);$fclose(trace_file);$finish;
   end
  end
  if(cycles>max_cycles) $fatal(1,"FAIL TEACH_SOC timeout pc=%h",dut.debug_wb_pc);
 end
 initial begin #2500000; $fatal(1,"FAIL TEACH_SOC absolute timeout"); end
endmodule
