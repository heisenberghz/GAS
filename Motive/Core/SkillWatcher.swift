//
//  SkillWatcher.swift
//  Motive
//
//  File watcher with debounce for skills directories.
//

import Foundation

final class SkillWatcher {
    typealias ChangeHandler = (_ changedPath: String?) -> Void

    private let debounceMs: Int
    private let onChange: ChangeHandler
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounceTimer: DispatchWorkItem?

    init(debounceMs: Int, onChange: @escaping ChangeHandler) {
        self.debounceMs = max(0, debounceMs)
        self.onChange = onChange
    }

    func startWatching(paths: [String]) {
        stop()
        let uniquePaths = Array(Set(paths)).filter { !$0.isEmpty }
        for path in uniquePaths {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .attrib],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                self?.notifyChange(changedPath: path)
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        debounceTimer?.cancel()
        debounceTimer = nil
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }

    func notifyChange(changedPath: String?) {
        debounceTimer?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange(changedPath)
        }
        debounceTimer = workItem
        let delay = DispatchTimeInterval.milliseconds(debounceMs)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
