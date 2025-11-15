#!/usr/bin/env python3
from pi5neo import Pi5Neo
import time
import psutil
import math
import random

# -------------------------
# CONFIGURATION
# -------------------------
NUM_LEDS = 8
SPI_DEVICE = '/dev/spidev0.0'
SPI_FREQ = 800

BRIGHTNESS_FACTOR = 0.15     # global brightness (kept modest)
BOOT_DELAY = 0.2
UPDATE_DELAY = 0.08          # faster for smoother animation

# CPU visualization settings
SMOOTHING_FACTOR = 0.3       # lower = more smoothing (0-1)
JITTER_INTENSITY = 0.12      # random fluctuation intensity (0-1)
WAVE_SPEED = 0.9             # scan speed (seconds per cycle-ish)

# Peak hold settings
PEAK_DECAY_PER_FRAME = 2.0   # percentage points per frame to decay peak

# Blinking for last LED
BLINK_FREQ = 2.0             # Hz, blink speed of last LED when active

neo = Pi5Neo(SPI_DEVICE, NUM_LEDS, SPI_FREQ)

# -------------------------
# HELPERS
# -------------------------
def scale_color(color, factor):
    r, g, b = color
    return (int(r * factor), int(g * factor), int(b * factor))

def set_led(i, color):
    r, g, b = color
    neo.set_led_color(i, r, g, b)

def update_strip():
    neo.update_strip()

# -------------------------
# BOOT ANIMATION
# -------------------------
def boot_animation():
    orange = (255, 165, 0)
    blue = (0, 0, 255)

    # Progressive alternate LEDs
    for i in range(NUM_LEDS):
        color = orange if i % 2 == 0 else blue
        set_led(i, scale_color(color, BRIGHTNESS_FACTOR * 2))  # Temporarily brighter for boot
        # dim background for previous LEDs
        for j in range(i):
            prev_color = orange if j % 2 == 0 else blue
            set_led(j, scale_color(prev_color, 0.05))
        update_strip()
        time.sleep(BOOT_DELAY)

    # Fade out progressively
    for i in reversed(range(NUM_LEDS)):
        for j in range(NUM_LEDS):
            if j >= i:
                set_led(j, (0, 0, 0))
            else:
                prev_color = orange if j % 2 == 0 else blue
                set_led(j, scale_color(prev_color, 0.05))
        update_strip()
        time.sleep(BOOT_DELAY)

# -------------------------
# CPU COLOR & WAVE HELPERS
# -------------------------
def get_color_for_led_position(led_index):
    """
    Color gradient based on LED position (always from left to right):
    - First 2 LEDs: Green
    - Next 2 LEDs: Yellow
    - Next 2 LEDs: Orange
    - Last 2 LEDs: Red
    """
    if led_index < 2:
        # Green for first 2 LEDs
        return (0, 255, 0)
    elif led_index < 4:
        # Yellow for next 2 LEDs
        return (255, 255, 0)
    elif led_index < 6:
        # Orange for next 2 LEDs
        return (255, 165, 0)
    else:
        # Red for last 2 LEDs
        return (255, 0, 0)

def wave_modulation(led_index, wave_position, cpu_level):
    """
    Stronger scan modulation for 'technical' feel.
    Returns a multiplier with higher amplitude at high CPU.
    """
    cpu_norm = max(0.0, min(1.0, cpu_level / 100.0))

    # Phase shifted along strip so it looks like scanning
    phase = (wave_position + led_index * 0.16) % 1.0
    s = (math.sin(phase * 2 * math.pi) + 1) / 2  # 0 -> 1

    # Sharpen the peak a bit (more like a blip)
    s = s ** 2

    # At low CPU, modulation is subtle; at high CPU it's stronger
    strength = 0.6 + 1.4 * (cpu_norm ** 1.2)  # stronger than before

    # Centered around 1.0, scaled by strength -> higher amplitude
    return 1.0 + strength * (s - 0.5)

# -------------------------
# TECHNICAL CPU DISPLAY
# -------------------------
def display_cpu_usage_technical(smoothed_usage, jitter_values, wave_position, peak_usage):
    """
    - Classic bar graph from left to right using green/yellow/orange/red
    - Smoothing + jitter on the frontier LED
    - Peak hold indicator with slow decay (same color as LED)
    - Strong scan modulation over the whole bar
    - Last LED blinks when active
    """
    now = time.time()
    # Square-wave blink for last LED
    blink_on = math.sin(2 * math.pi * BLINK_FREQ * now) > 0

    # Non-blocking read (uses time since last call)
    current_usage = psutil.cpu_percent(interval=None)

    # Smooth CPU
    new_smoothed = (smoothed_usage * (1 - SMOOTHING_FACTOR) +
                    current_usage * SMOOTHING_FACTOR)

    # Determine how many LEDs should be on
    target_leds = (new_smoothed / 100.0) * NUM_LEDS

    # Update peak usage with decay
    if new_smoothed > peak_usage:
        peak_usage = new_smoothed
    else:
        peak_usage = max(0.0, peak_usage - PEAK_DECAY_PER_FRAME)

    # Peak LED index
    if peak_usage <= 0:
        peak_led = None
    else:
        peak_pos = (peak_usage / 100.0) * NUM_LEDS
        peak_led = int(max(0, min(NUM_LEDS - 1, peak_pos - 1e-6)))

    # Update jitter
    for i in range(NUM_LEDS):
        jitter_values[i] = jitter_values[i] * 0.5 + random.uniform(-1, 1) * JITTER_INTENSITY

    # Clear strip
    for i in range(NUM_LEDS):
        set_led(i, (0, 0, 0))

    # Render LEDs
    for i in range(NUM_LEDS):
        base_color = get_color_for_led_position(i)

        # Base bar brightness
        brightness = 0.0
        if i < int(target_leds):
            # fully on LEDs
            brightness = 1.0
        elif i == int(target_leds):
            # partial frontier LED with jitter
            frac = target_leds - int(target_leds)
            brightness = max(0.0, min(1.0, frac + jitter_values[i]))

        # Very faint idle glow for LEDs just past the bar for a more "data" look
        if brightness == 0.0 and i == int(target_leds) + 1 and new_smoothed > 3:
            brightness = max(0.0, min(0.15, 0.1 + 0.05 * jitter_values[i]))

        # Apply scan modulation
        scan_mult = wave_modulation(i, wave_position, new_smoothed)
        brightness *= scan_mult

        # Apply peak marker override (keep pure color, just brighter)
        if peak_led is not None and i == peak_led:
            brightness = max(brightness, 1.1)

        # Last LED blinking when active
        if i == NUM_LEDS - 1 and brightness > 0.0:
            # When blink_off, mostly off but keep a tiny hint so it's not harsh
            if not blink_on:
                brightness *= 0.15  # dim but not totally off

        # Clamp brightness (allow higher peaks)
        brightness = max(0.0, min(2.0, brightness))

        # Apply global brightness factor
        r, g, b = base_color
        final_color = (
            int(max(0, min(255, r * brightness * BRIGHTNESS_FACTOR))),
            int(max(0, min(255, g * brightness * BRIGHTNESS_FACTOR))),
            int(max(0, min(255, b * brightness * BRIGHTNESS_FACTOR))),
        )

        set_led(i, final_color)

    update_strip()
    return new_smoothed, peak_usage

# -------------------------
# MAIN
# -------------------------
if __name__ == "__main__":
    print("Boot animation (alternate orange/blue LEDs)...")
    boot_animation()
    print("Displaying CPU usage with technical bar, peak hold, scan, and blinking last LED...")

    smoothed_usage = 0.0
    jitter_values = [0.0] * NUM_LEDS
    wave_position = 0.0
    peak_usage = 0.0

    # Initialize psutil baseline
    psutil.cpu_percent(interval=None)

    while True:
        smoothed_usage, peak_usage = display_cpu_usage_technical(
            smoothed_usage, jitter_values, wave_position, peak_usage
        )

        # Update wave position for scan animation
        wave_position += UPDATE_DELAY / WAVE_SPEED
        if wave_position >= 1.0:
            wave_position -= 1.0

        time.sleep(UPDATE_DELAY)
