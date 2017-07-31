
module Project
	(
		CLOCK_50,						//	On Board 50 MHz
		// Your inputs and outputs here
        KEY,
        SW,
		  HEX0,
		  HEX4,
		  HEX5,
		  HEX6,
		  HEX7,
		  LEDR,
		// The ports below are for the VGA output.  Do not change.
		VGA_CLK,   						//	VGA Clock
		VGA_HS,							//	VGA H_SYNC
		VGA_VS,							//	VGA V_SYNC
		VGA_BLANK_N,						//	VGA BLANK
		VGA_SYNC_N,						//	VGA SYNC
		VGA_R,   						//	VGA Red[9:0]
		VGA_G,	 						//	VGA Green[9:0]
		VGA_B   						//	VGA Blue[9:0]
	);

	input	CLOCK_50;				//	50 MHz
	input   [17:0]   SW;
	input   [3:0]   KEY;
	output   [6:0]   HEX0;
	output [6:0] HEX4;
	output [6:0] HEX5;
	output [6:0] HEX6;
	output [6:0] HEX7;
	output [4:0] LEDR;

	// Declare your inputs and outputs here
	// Do not change the following outputs
	output			VGA_CLK;   				//	VGA Clock
	output			VGA_HS;					//	VGA H_SYNC
	output			VGA_VS;					//	VGA V_SYNC
	output			VGA_BLANK_N;				//	VGA BLANK
	output			VGA_SYNC_N;				//	VGA SYNC
	output	[9:0]	VGA_R;   				//	VGA Red[9:0]
	output	[9:0]	VGA_G;	 				//	VGA Green[9:0]
	output	[9:0]	VGA_B;   				//	VGA Blue[9:0]

	// Create the colour, x, y and writeEn wires that are inputs to the controller.
	wire [2:0] colour;
	wire [7:0] x;
	wire [6:0] y;
	wire ldx, ldy, ldc, enable, js_enter;
	// wires between control and datapath
    wire [1:0] js_out;
	wire js_entered;
	wire move_done, move_p;
	wire get_random;
	wire [1:0] random_out;
	wire reset_n;
	wire get_input;
	wire get_random_g;
	wire get_random_d;
	wire get_verify;
	wire match_out;
	wire lost;
	assign reset_n = SW[17];

	// Create an Instance of a VGA controller - there can be only one!
	// Define the number of colours as well as the initial background
	// image file (.MIF) for the controller.
	vga_adapter VGA(
			.resetn(reset_n),
			.clock(CLOCK_50),
			.colour(colour),
			.x(x),
			.y(y),
			.plot(1),
			/* Signals for the DAC to drive the monitor. */
			.VGA_R(VGA_R),
			.VGA_G(VGA_G),
			.VGA_B(VGA_B),
			.VGA_HS(VGA_HS),
			.VGA_VS(VGA_VS),
			.VGA_BLANK(VGA_BLANK_N),
			.VGA_SYNC(VGA_SYNC_N),
			.VGA_CLK(VGA_CLK));
		defparam VGA.RESOLUTION = "160x120";
		defparam VGA.MONOCHROME = "FALSE";
		defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
		defparam VGA.BACKGROUND_IMAGE = "black.mif";

	// Put your code here. Your code should produce signals x,y,colour and writeEn/plot
	// for the VGA controller, in addition to any other functionality your design may require.

	// Create an instance of datapath
	datapath d0(.clk(CLOCK_50),
				.joystick(KEY[3:0]),
				.reset_n(reset_n),
				.move_p(move_p),
				.x_out(x),
				.y_out(y),
				.colour_out(colour),
				.move_done(move_done),
				.get_input(get_input),
				.get_random_gen(get_random_g),
				.get_random_disp(get_random_d),
				.get_verify(get_verify),
				.match_out(match_out),
				.js_entered(js_entered),
				.HEX0(HEX0),
				.HEX4(HEX4),
				.HEX5(HEX5),
				.HEX6(HEX6),
				.HEX7(HEX7),
				.lost(lost)
				);

	// Create an instance of control
	control c0(.clk(CLOCK_50),
			   .reset_n(reset_n),
			   .start_button(SW[0]),
			   .js_entered(js_entered),
			   .move_done(move_done),
			   .match_out(match_out),
			   .move_p(move_p),
			   .get_random_gen (get_random_g),
			   .get_random_disp (get_random_d),
		       .get_input(get_input),
		       .get_verify(get_verify),
				 .LEDR(LEDR)
			   );

endmodule


module datapath(clk, joystick, reset_n, move_p, x_out, y_out, colour_out, move_done, get_input, get_random_gen, get_random_disp, get_verify, match_out, js_entered,
HEX0, HEX4, HEX5, HEX6, HEX7, lost);

	// Declare inputs and outputs
	input clk;
	input [3:0] joystick;
	input reset_n;
	input move_p;
	input lost;

	output [7:0] x_out;
	output [7:0] y_out;
	output [2:0] colour_out;
	output reg move_done;
	output [6:0] HEX0;
	output [6:0] HEX4;
	output [6:0] HEX5;
	output [6:0] HEX6;
	output [6:0] HEX7;

	reg [7:0] count;
	reg [7:0] p_x;
	reg [7:0] p_y;
	reg [2:0] color;

	wire enable_y;
	wire get_random;
	wire [1:0] random_out;

	input get_input;
	input get_random_gen;
	input get_random_disp;
	input get_verify;
	output reg match_out;
	output reg js_entered;
	reg dir;

	// Declare an instance of player to keep track of where the player is.
	player my_player(.clk(clk), .x(p_x), .y(p_y), .reset(reset_n), .x_out(x_out), .y_out(y_out), .colour(colour_out));

	// Wire for rate divider, this is for how fast the player animation updates.
	wire [27:0] rate;
	rateDivider rd_10(clk, 1, 1'b1, 28'd1250000, rate);
	wire display_clk;
	assign display_clk = (rate == 28'b0) ? 1 : 0;

	// Create a counter to move the player 39 pixels, reaching an edge of the screen
	always @(posedge display_clk)
		begin
		move_done <= 1'b0;
		// Counter resets to 0
		if (!reset_n | !move_p | lost)
			count <= 8'b0;
		else if (move_p) begin
			count <= count + 1'b1;
			// When the moving animation is completed let the control know.
			if (count == 8'd39) begin
				count <= 8'b0;
				move_done <= 1'b1;
			end
		end
	end

	// joystick controller
	localparam right             	 = 2'b00,
			   left                  = 2'b01,
			   up                    = 2'b10,
			   down                  = 2'b11;

	// Match the input of the keys with the direction, signal to control that a key is entered
	always @(posedge clk)
		begin
		if (!reset_n) begin
			dir <= 2'b00;
			js_entered <= 1'b0;
		end
		else begin
			if (get_input)
				begin
				// Right
				if (joystick == 4'b1101) begin
					dir <= right;
					js_entered <= 1'b1;
				end
				// Left
				else if (joystick == 4'b0111) begin
					dir <= left;
					js_entered <= 1'b1;
				end
				// Up
				else if (joystick == 4'b1011) begin
					dir <= up;
					js_entered <= 1'b1;
				end
				// Down
				else if (joystick == 4'b1110) begin
					dir <= down;
					js_entered <= 1'b1;
				end
			end
			else begin
				js_entered <= 1'b0;
			end
		end
	end

	//Determine which direction the player will move to, and update the animation.
	always @(*)
	begin
		p_x = 7'd80;
		p_y = 7'd60;
		case(dir)
			2'b00 : p_x = 7'd80 + count; //right
			2'b01 : p_x = 7'd80 - count; //left
			2'b10 : p_y = 7'd60 + count; //up
			2'b11 : p_y = 7'd60 - count; //down
		endcase
	end

	// random number generator to generate a random direction.
	reg [1:0] rand_num_back;
	reg [1:0] rand_num_display;
	reg [1:0] storage;

	always @(posedge clk)
	begin
		if (!reset_n | lost) begin
			storage <= 2'b00;
			rand_num_back <= 2'b00;
			rand_num_display <= 2'b00;
		end
		else begin
			if (get_random_gen)
			begin
				rand_num_back <= storage;
			end
			else
			begin
				if (storage == 2'b11) begin
					storage <= 2'b00;
				end
				else begin
					storage <= storage + 2'b01;
				end
			end
			if (get_random_disp) begin
				rand_num_display <= rand_num_back;
			end
		end
	end

	// Display the random direction to the hex display.
	instr_decoder my_dec(.instr_digit(rand_num_display), .segments(HEX0));

	// Check whether the user's input matches with the instruction
	reg [7:0] score;
	always @(posedge clk)
	begin
		if (!reset_n | lost) begin
			match_out <= 1'b0;
			score <= 8'd0;
		end
		else begin
			if (get_verify)
			begin
				// If it is a match then increment the score by one
				if (dir == rand_num_display)
				begin
					score <= score + 1'b1;
					match_out <= 1'b1;
				end
				else
				begin
					match_out <= 1'b0;
				end
			end
		end
	end

	// Display the score
	hexdisplay h4(score[3:0], HEX4);
	hexdisplay h5(score[7:4], HEX5);

	// Display the counter of player animation for debug purposes
	hexdisplay h6(count[3:0], HEX6);
	hexdisplay h7(count[7:4], HEX7);
endmodule

module control(input clk,
	       input reset_n ,
		   input start_button,
	       input js_entered,
	       input move_done,
		   input match_out,

	       output reg move_p,
	       output reg get_random_gen,
		   output reg get_random_disp,
		   output reg get_input,
		   output reg get_verify,
			output reg [4:0]LEDR,
		output reg lost
		   );


	reg [2:0] current_state, next_state;

	// States
	localparam  init                 = 3'd0,
				wait_for_in          = 3'd1,
				move				 = 3'd2,
				verify				 = 3'd3,
				lose				 = 3'd4;


	reg init_done;
	// State Table
	always @(*)
	begin : state_table
		case (current_state)
			init: next_state = start_button ? wait_for_in: init; // start screen. Will begin when the user presses the start button. Also generates the first instruction
			wait_for_in: next_state = js_entered? move : wait_for_in;// will stay in this state until a input is entered
			move: next_state = move_done ? verify : move; // will move until the movement is done
			verify: next_state = match_out ? wait_for_in : lose; // will check the validity of the instruction. If correct input go to wait for input else go to lose
			lose: next_state = start_button ? init: lose; // when lose, return to init stage
			default: next_state = init;
		endcase
	end
	// Output Logic
	always @(*) begin
		// By default everything is 0.
		move_p = 1'b0;
		get_random_gen = 1'b0;
		get_random_disp = 1'b0;
		get_input = 1'b0;
		get_verify = 1'b0;
		LEDR = 5'b00000;
		lost = 1'b0;

		case (current_state)
			init: begin
				// Get a random instruction in the initial state
				LEDR = 5'b00001;
				get_random_gen = 1'b1;
			end
			wait_for_in: begin
				// Allow for an input to be entered and display the random instruction
				LEDR = 5'b00010;
				get_input = 1'b1;
				get_random_disp = 1'b1;
			end
			move: begin
				// Allow the player animation to start
				LEDR = 5'b00100;
				move_p = 1'b1;
			end
			verify: begin
				// After the player animation is done, verify the input with the instruction
				LEDR = 5'b01000;
				get_verify = 1'b1;
				get_random_gen = 1'b1;
			end
			lose: begin
				// If the player loses then signal to reset everything.
				LEDR = 5'b10000;
				lost = 1'b1;
			end

		endcase
	end

	// Current State Register
	always @(posedge clk)
	begin: state_FFs
		if (!reset_n)
			current_state <= init;
		else
			current_state <= next_state;
	end

endmodule

// Module to draw a player, top left pixel is x, y
module player(
  input clk,
  input [7:0] x,
  input [7:0] y,
  input reset,
  output  [7:0] x_out,
  output  [7:0] y_out,
  output reg [2:0] colour
  );

  reg [2:0] count_x, count_y;
	reg [3:0] count;
  // Counting up to 24 because we need 24 pixels to draw the player
  always @(posedge clk) begin
    if (!reset) begin
			colour <= 3'b000;
			count <= count + 4'd1;
			if ( count == 4'd24) begin
				count <= 4'd0;
			end
		end
    else begin
			colour <= 3'b111;
      count <= count + 4'd1;
			if ( count == 4'd24) begin
				count <= 4'd0;
			end
		end
  end

	// Case table to draw the plater
	always @(*) begin
			case (count)
					4'd1: begin count_x = 4'd0; count_y = 4'd0; end
					4'd2: begin count_x = 4'd1; count_y = 4'd0; end
					4'd3: begin count_x = 4'd2; count_y = 4'd0; end
					4'd4: begin count_x = 4'd3; count_y = 4'd0; end
					4'd5: begin count_x = 4'd4; count_y = 4'd0; end
					4'd6: begin count_x = 4'd5; count_y = 4'd0; end
					4'd7: begin count_x = 4'd5; count_y = 4'd1; end
					4'd8: begin count_x = 4'd5; count_y = 4'd2; end
					4'd9: begin count_x = 4'd5; count_y = 4'd3; end
					4'd10: begin count_x = 4'd5; count_y = 4'd4; end
					4'd11: begin count_x = 4'd5; count_y = 4'd5; end
					4'd12: begin count_x = 4'd4; count_y = 4'd5; end
					4'd13: begin count_x = 4'd3; count_y = 4'd5; end
					4'd14: begin count_x = 4'd2; count_y = 4'd5; end
					4'd15: begin count_x = 4'd1; count_y = 4'd5; end
					4'd16: begin count_x = 4'd0; count_y = 4'd5; end
					4'd17: begin count_x = 4'd0; count_y = 4'd4; end
					4'd18: begin count_x = 4'd0; count_y = 4'd3; end
					4'd19: begin count_x = 4'd0; count_y = 4'd2; end
					4'd20: begin count_x = 4'd0; count_y = 4'd1; end
					4'd21: begin count_x = 4'd1; count_y = 4'd1; end
					4'd22: begin count_x = 4'd1; count_y = 4'd4; end
					4'd23: begin count_x = 4'd4; count_y = 4'd4; end
					4'd24: begin count_x = 4'd4; count_y = 4'd1; end
					default: begin count_x = 4'd0; count_y = 4'd0; end
			endcase
	end

	// Assign which pixel to draw.
	assign x_out = x + count_x;
	assign y_out = y + count_y;
endmodule

// Draw display timer, top left of timer is x, y
module displayTimer(
  input clk,
  input [7:0] x,
  input [7:0] y,
  input reset,
  output [7:0] x_out,
  output [7:0] y_out,
  output reg [2:0] colour
  );

  reg [6:0] count_x;
  // The timer is 99 pixels long, aka. length of board.
	always @(posedge clk) begin
    if (!reset) begin
      count_x <= 7'd0;
			colour <= 3'b000;
		end
    else begin
			colour <= 3'b111;
      count_x <= count_x + 1;
			if ( count_x == 7'd99) begin
				count_x <= 4'd0;
			end
		end
  end

  assign x_out = x + count_x;
  assign y_out = y;
endmodule

// Rate divider
module rateDivider(clk, Clear_b, Enable, d, q);
	input clk;
	input Clear_b;
	input Enable;
	input [27:0] d;

	output [27:0] q;
	reg [27:0] q;


	always @(posedge clk)
	begin
	if (q == 0)
		if (Clear_b == 0)
			q<=0;
		else
			q<=d;
	else if(Enable == 1)
		q<=q-1;
	else if (Enable == 0)
		q<=q;
	end
endmodule

// Decode direction instruction to display on hex
module instr_decoder(instr_digit, segments);
    input [1:0] instr_digit;
    output reg [6:0] segments;

    always @(*)
        case (instr_digit)
            2'b00: segments = 7'b100_1110;//r
            2'b01: segments = 7'b100_0111;//l
            2'b10: segments = 7'b100_0001;//u
            2'b11: segments = 7'b010_0001;//d
            default: segments = 7'b111_1111;
        endcase
endmodule

// Display a number onto hex.
module hexdisplay(hex_num, segs);
    input [3:0] hex_num;
    output reg [6:0] segs;

    always @(*)
        case (hex_num)
            4'h0: segs = 7'b100_0000;
            4'h1: segs = 7'b111_1001;
            4'h2: segs = 7'b010_0100;
            4'h3: segs = 7'b011_0000;
            4'h4: segs = 7'b001_1001;
            4'h5: segs = 7'b001_0010;
            4'h6: segs = 7'b000_0010;
            4'h7: segs = 7'b111_1000;
            4'h8: segs = 7'b000_0000;
            4'h9: segs = 7'b001_1000;
            4'hA: segs = 7'b000_1000;
            4'hB: segs = 7'b000_0011;
            4'hC: segs = 7'b100_0110;
            4'hD: segs = 7'b010_0001;
            4'hE: segs = 7'b000_0110;
            4'hF: segs = 7'b000_1110;
            default: segs = 7'h7f;
        endcase
endmodule
