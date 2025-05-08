# SPDX-FileCopyrightText: © 2025 Anton Maurovic
# SPDX-License-Identifier: Apache-2.0

# This is based on https://github.com/algofoogle/ttihp0p2-raybox-zero/blob/main/test/test.py,
# with SPI stuff removed.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ClockCycles
import time
from os import environ as env
import re
from pathlib import Path

HIGH_RES        = float(env.get('HIGH_RES')) if 'HIGH_RES' in env else None # If not None, scale H res by this, and step by CLOCK_PERIOD/HIGH_RES instead of unit clock cycles.
CLOCK_PERIOD    = float(env.get('CLOCK_PERIOD') or 40.0) # Default 40.0 (period of clk oscillator input, in nanoseconds)
FRAMES          =   int(env.get('FRAMES')       or    3) # Default 3 (total frames to render)
# INC_PX          =   int(env.get('INC_PX')       or    1) # Default 1 (inc_px on)
# INC_PY          =   int(env.get('INC_PY')       or    1) # Default 1 (inc_py on)
# GEN_TEX         =   int(env.get('GEN_TEX')      or    0) # Default 0 (use tex ROM; no generated textures)
# DEBUG_POV       =   int(env.get('DEBUG_POV')    or    1) # Default 1 (show POV vectors debug)
# REG             =   int(env.get('REG')          or    0) # Default 0 (UNregistered outputs)

print(f"""
Test parameters (can be overridden using ENV vars):
---     HIGH_RES: {HIGH_RES}
--- CLOCK_PERIOD: {CLOCK_PERIOD}
---       FRAMES: {FRAMES}
""");
# ---       INC_PX: {INC_PX}
# ---       INC_PY: {INC_PY}
# ---      GEN_TEX: {GEN_TEX}
# ---    DEBUG_POV: {DEBUG_POV}
# ---          REG: {REG}

# Make sure all bidir pins are configured as they should be,
# for this design:
def check_uio_out(dut):
    # Make sure 5 LSB are outputs, and 3 MSB are inputs:
    assert re.match('00011111', dut.uio_oe.value.binstr)


# This can represent hard-wired stuff:
def set_default_start_state(dut):
    dut.ena.value = 1
    dut.mode.value = 0 # Normal 640x480 60fps mode
    dut.adj_hrs.value = 0
    dut.adj_min.value = 0
    dut.adj_sec.value = 1
    dut.show_clock.value = 1
    dut.pmod_select.value = 0 # Tiny VGA PMOD mode.

@cocotb.test()
async def test_frames(dut):
    """
    Generate a number of full video frames and write to frames_out/frame-###.ppm
    """

    dut._log.info("Starting test_frames...")

    frame_count = FRAMES # No. of frames to render.
    hrange = 800
    frame_height = 525
    vrange = frame_height
    hres = HIGH_RES or 1

    print(f"Rendering {frame_count} full frame(s)...")

    set_default_start_state(dut)
    # Start with reset released:
    dut.rst_n.value = 1

    clk = Clock(dut.clk, CLOCK_PERIOD, units="ns")
    cocotb.start_soon(clk.start())

    # Wait 3 clocks...
    await ClockCycles(dut.clk, 3)
    check_uio_out(dut)
    dut._log.info("Assert reset...")
    # ...then assert reset:
    dut.rst_n.value = 0
    # ...and wait another 10 clocks...
    await ClockCycles(dut.clk, 10)
    check_uio_out(dut)
    dut._log.info("Release reset...")
    # ...then release reset:
    dut.rst_n.value = 1
    x_count = 0 # Counts unknown signal values.
    z_count = 0
    sample_count = 0 # Total count of pixels or samples.

    Path( 'frames_out' ).mkdir( exist_ok=True ) # Make sure frames_out dir exists.

    for frame in range(frame_count):
        render_start_time = time.time()

        nframe = frame + 1

        # Create PPM file to visualise the frame, and write its header:
        img = open(f"frames_out/frame-{frame:03d}.ppm", "w")
        img.write("P3\n")
        img.write(f"{int(hrange*hres)} {vrange:d}\n")
        img.write("255\n")

        for n in range(vrange): # 525 lines * however many frames in frame_count
            print(f"Rendering line {n} of frame {frame}")
            for n in range(int(hrange*hres)): # 800 pixel clocks per line.
                if n % 100 == 0:
                    print('.', end='')
                if 'x' in dut.rgb.value.binstr:
                    # Output is unknown; make it green:
                    r = 0
                    g = 255
                    b = 0
                elif 'z' in dut.rgb.value.binstr:
                    # Output is HiZ; make it magenta:
                    r = 255
                    g = 0
                    b = 255
                else:
                    rr = int(dut.rr.value)
                    gg = int(dut.gg.value)
                    bb = int(dut.bb.value)
                    # Scale 2-bit colour to 8-bit colour,
                    # e.g. expand 0b00000010 to 0b10101010:
                    rr &= 0b11; rr = rr | (rr<<2) | (rr<<4) | (rr<<6)
                    gg &= 0b11; gg = gg | (gg<<2) | (gg<<4) | (gg<<6)
                    bb &= 0b11; bb = bb | (bb<<2) | (bb<<4) | (bb<<6)
                    hsyncb = 255 if dut.hsync.value.binstr=='x' else (0==dut.hsync.value)*0b110000
                    vsyncb = 128 if dut.vsync.value.binstr=='x' else (0==dut.vsync.value)*0b110000
                    r = rr | hsyncb
                    g = gg | vsyncb
                    b = bb
                sample_count += 1
                if 'x' in (dut.rgb.value.binstr + dut.hsync.value.binstr + dut.vsync.value.binstr):
                    x_count += 1
                if 'z' in (dut.rgb.value.binstr + dut.hsync.value.binstr + dut.vsync.value.binstr):
                    z_count += 1
                img.write(f"{r} {g} {b}\n")
                if HIGH_RES is None:
                    await ClockCycles(dut.clk, 1) 
                else:
                    await Timer(CLOCK_PERIOD/hres, units='ns')
        img.close()
        render_stop_time = time.time()
        delta = render_stop_time - render_start_time
        print(f"[{render_stop_time}: Frame simulated in {delta} seconds]")
    print("Waiting 1 more clock, for start of next line...")
    await ClockCycles(dut.clk, 1)

    # await toggler

    print(f"DONE: Out of {sample_count} pixels/samples, got: {x_count} 'x'; {z_count} 'z'")
