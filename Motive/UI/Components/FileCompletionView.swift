//
//  FileCompletionView.swift
//  Motive
//
//  Shared file completion popup for @ mentions
//

import SwiftUI

struct FileCompletionView: View {
    let items: [FileCompletionItem]
    let selectedIndex: Int
    let currentPath: String
    let onSelect: (FileCompletionItem) -> Void
    var showFooter: Bool = false // Only show footer in Drawer, not CommandBar
    var maxHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Path breadcrumb
            if !currentPath.isEmpty {
                HStack(spacing: AuroraSpacing.space1) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.Aurora.textMuted)

                    Text("@\(currentPath)/")
                        .font(.Aurora.micro)
                        .foregroundColor(Color.Aurora.textMuted)

                    Spacer()
                }
                .padding(.horizontal, AuroraSpacing.space3)
                .padding(.vertical, AuroraSpacing.space2)
                .background(Color.Aurora.surface.opacity(0.5))
            }

            // Items list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            FileCompletionItemView(
                                item: item,
                                isSelected: index == selectedIndex
                            ) {
                                onSelect(item)
                            }
                            .id(index)
                        }
                    }
                    .padding(.vertical, AuroraSpacing.space2)
                    .padding(.horizontal, AuroraSpacing.space2)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation(.auroraFast) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: maxHeight)
    }
}

// MARK: - File Completion Item View

private struct FileCompletionItemView: View {
    let item: FileCompletionItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AuroraSpacing.space3) {
                // Icon
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 20)

                // Name
                Text(item.name)
                    .font(.Aurora.body)
                    .foregroundColor(Color.Aurora.textPrimary)
                    .lineLimit(1)

                // Directory indicator
                if item.isDirectory {
                    Text("/")
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                }

                Spacer()

                // Size (for files)
                if let size = item.sizeString {
                    Text(size)
                        .font(.Aurora.micro)
                        .foregroundColor(Color.Aurora.textMuted)
                }

                // Selection indicator
                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.Aurora.textMuted)
                }
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space2)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(isSelected ? Color.Aurora.accent.opacity(0.1) : (isHovering ? Color.Aurora.glassOverlay.opacity(0.06) : Color.clear))
            )
            .overlay(
                HStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.Aurora.auroraGradient)
                            .frame(width: 3)
                    }
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var iconColor: Color {
        if item.isDirectory {
            return Color.Aurora.accent
        }
        return isSelected ? Color.Aurora.accent : Color.Aurora.textSecondary
    }
}

// MARK: - File Completion Popup Modifier

struct FileCompletionPopup: ViewModifier {
    @Binding var isShowing: Bool
    let items: [FileCompletionItem]
    let selectedIndex: Int
    let currentPath: String
    let onSelect: (FileCompletionItem) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isShowing, !items.isEmpty {
                    FileCompletionView(
                        items: items,
                        selectedIndex: selectedIndex,
                        currentPath: currentPath,
                        onSelect: onSelect
                    )
                    .background(
                        RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                            .fill(Color.Aurora.backgroundDeep)
                            .shadow(color: Color.black.opacity(0.2), radius: 12, y: -4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                            .stroke(Color.Aurora.border, lineWidth: 0.5)
                    )
                    .padding(.horizontal, AuroraSpacing.space3)
                    .padding(.bottom, AuroraSpacing.space2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
    }
}

extension View {
    func fileCompletionPopup(
        isShowing: Binding<Bool>,
        items: [FileCompletionItem],
        selectedIndex: Int,
        currentPath: String,
        onSelect: @escaping (FileCompletionItem) -> Void
    ) -> some View {
        modifier(FileCompletionPopup(
            isShowing: isShowing,
            items: items,
            selectedIndex: selectedIndex,
            currentPath: currentPath,
            onSelect: onSelect
        ))
    }
}
