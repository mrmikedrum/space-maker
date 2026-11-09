import Foundation
import MachO

/// Finds symbols that a loaded Mach-O image does not export, by walking its symbol table in memory.
///
/// `dlsym` only sees exported symbols. Some SkyLight entry points Space Maker needs are file-local
/// (`static`) C++ functions, so they have to be located through `LC_SYMTAB` instead.
/// Ported from yabai's `src/misc/macho_dlsym.h`.
enum MachOSymbols {
    static func find(symbol: String, inImage imagePath: String) -> UnsafeMutableRawPointer? {
        guard let (header, slide) = loadedImage(path: imagePath) else { return nil }

        var linkedit: UnsafePointer<segment_command_64>?
        var symtab: UnsafePointer<symtab_command>?
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let loadCommand = command.assumingMemoryBound(to: load_command.self)
            switch loadCommand.pointee.cmd {
            case UInt32(LC_SEGMENT_64):
                let segment = command.assumingMemoryBound(to: segment_command_64.self)
                if segmentName(segment) == SEG_LINKEDIT { linkedit = segment }
            case UInt32(LC_SYMTAB):
                symtab = command.assumingMemoryBound(to: symtab_command.self)
            default:
                break
            }
            command = command.advanced(by: Int(loadCommand.pointee.cmdsize))
        }
        guard let linkedit, let symtab else { return nil }

        let linkeditBase = Int(linkedit.pointee.vmaddr) - Int(linkedit.pointee.fileoff) + slide
        guard let strings = UnsafeRawPointer(bitPattern: linkeditBase + Int(symtab.pointee.stroff)),
              let symbols = UnsafeRawPointer(bitPattern: linkeditBase + Int(symtab.pointee.symoff))
        else { return nil }

        let entries = symbols.assumingMemoryBound(to: nlist_64.self)
        return symbol.withCString { target in
            for index in 0..<Int(symtab.pointee.nsyms) {
                let entry = entries[index]
                let name = strings.advanced(by: Int(entry.n_un.n_strx)).assumingMemoryBound(to: CChar.self)
                if strcmp(name, target) == 0 {
                    return UnsafeMutableRawPointer(bitPattern: Int(entry.n_value) + slide)
                }
            }
            return nil
        }
    }

    private static func loadedImage(path: String) -> (UnsafePointer<mach_header_64>, Int)? {
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index), String(cString: name) == path,
                  let header = _dyld_get_image_header(index)
            else { continue }
            let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
            return (header64, _dyld_get_image_vmaddr_slide(index))
        }
        return nil
    }

    private static func segmentName(_ segment: UnsafePointer<segment_command_64>) -> String {
        withUnsafeBytes(of: segment.pointee.segname) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
