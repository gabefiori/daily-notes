package main

import "core:fmt"
import "core:mem"
import os "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:sys/posix"
import "core:time"

ARENA_BUFFER: [mem.Megabyte]byte
DATE_BUFFER: [time.MIN_YYYY_DATE_LEN + 3]byte
NOTE_BUFFER: [time.MIN_YYYY_DATE_LEN + 5]byte

DEFAULT_NOTES_DIR :: "~/notes"

main :: proc() {
	arena: mem.Arena
	mem.arena_init(&arena, ARENA_BUFFER[:])
	arena_allocator := mem.arena_allocator(&arena)

	exit_code := 0
	defer os.exit(exit_code)

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, arena_allocator)
		arena_allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintfln("===== %v allocations not freed: =====", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintfln("- %v bytes @ %v", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	exit_code = run(arena_allocator)
	free_all(arena_allocator)
}

run :: proc(allocator := context.allocator) -> (exit_code: int) {
	current_time := time.now()

	root_dir := os.get_env("DAILY_NOTES_DIR", allocator)
	if root_dir == "" {
		root_dir = DEFAULT_NOTES_DIR
	}

	expanded_dir, expand_err := expand_path(root_dir, allocator)
	if expand_err != .None {
		fmt.eprintfln("failed to expand path '%s' (%s)", root_dir, expand_err)
		return 1
	}
	root_dir = expanded_dir

	fill_date_buffer(current_time, DATE_BUFFER[:], '/')
	copy(DATE_BUFFER[time.MIN_YYYY_DATE_LEN:], ".md")

	file_path := filepath.join({root_dir, string(DATE_BUFFER[:])}, allocator)
	dir_path := string(file_path[:len(file_path) - 5])

	editor := os.get_env("EDITOR", allocator)
	c_editor := strings.clone_to_cstring(editor, allocator)
	c_path := strings.clone_to_cstring(file_path, allocator)

	when ODIN_DEBUG {
		fmt.println("===== DEBUG VALUES =====")
		fmt.printfln("editor: '%s', filepath: '%s'", editor, file_path)
		return 0
	}

	if os.is_file(file_path) {
		return open_editor(c_editor, c_path)
	}

	if !os.is_dir(dir_path) {
		if err := os.mkdir_all(dir_path); err != nil {
			fmt.eprintfln("failed to create dir '%s' (%s)", dir_path, err)
			return 1
		}
	}

	copy(NOTE_BUFFER[:], "# ")
	copy(NOTE_BUFFER[12:], "\n\n\n")
	fill_date_buffer(current_time, NOTE_BUFFER[2:12], '-')

	err := os.write_entire_file(file_path, NOTE_BUFFER[:])
	if err != nil {
		fmt.eprintfln("failed to write file '%s' (%s)", file_path, err)
		return 1
	}

	return open_editor(c_editor, c_path)
}

open_editor :: proc(editor, path: cstring, allocator := context.allocator) -> (exit_code: int) {
	when ODIN_DEBUG {
		return 0
	}

	ret := posix.execlp(editor, editor, path, nil)
	fmt.eprintfln("could not execute: %v, %v", ret, posix.strerror(posix.errno()))
	return 1
}
