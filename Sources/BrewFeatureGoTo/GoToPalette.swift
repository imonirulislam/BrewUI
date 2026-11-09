//
//  GoToPalette.swift
//  BrewFeatureGoTo
//

import BrewAppEnvironment
import BrewCore
import BrewRepositoryInterfaces
import BrewUIComponents
import SwiftUI

public struct GoToPaletteRoot: View {
    @Environment(\.installedPackagesRepository) private var installedRepository
    @Environment(\.catalogueRepository) private var catalogueRepository

    private let pages: [GoToPage]
    private let onSelect: (GoToDestination) -> Void

    public init(pages: [GoToPage], onSelect: @escaping (GoToDestination) -> Void) {
        self.pages = pages
        self.onSelect = onSelect
    }

    public var body: some View {
        GoToPalette(
            viewModel: GoToViewModel(pages: pages, installedRepository: installedRepository, catalogueRepository: catalogueRepository),
            onSelect: onSelect,
        )
    }
}

struct GoToPalette: View {
    @State private var viewModel: GoToViewModel
    @State private var query = ""
    @FocusState private var fieldIsFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let onSelect: (GoToDestination) -> Void

    /// Long enough to skip a catalogue search per keystroke while typing quickly.
    private static let searchDelay: Duration = .milliseconds(120)

    init(viewModel: GoToViewModel, onSelect: @escaping (GoToDestination) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: BrewSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.brewTextSecondary)
                    .accessibilityHidden(true)
                TextField(String(localized: "Go to page or package", bundle: #bundle, comment: "Go to palette: search field placeholder"),
                          text: $query)
                    .textFieldStyle(.plain)
                    .font(.brewTitle3)
                    .focused($fieldIsFocused)
                    .onSubmit(activateHighlighted)
                    .onKeyPress(.downArrow) {
                        viewModel.moveHighlight(by: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        viewModel.moveHighlight(by: -1)
                        return .handled
                    }
                    .onExitCommand { dismiss() }
            }
            .padding(BrewSpacing.lg)

            Divider()

            if viewModel.results.isEmpty {
                Text("No pages or packages match", bundle: #bundle, comment: "Go to palette: no results")
                    .foregroundStyle(Color.brewTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrewSpacing.xl)
            } else {
                resultsList
                    .frame(height: resultsHeight)
            }
        }
        .frame(width: 560)
        .background(Color.brewSurfaceElevated)
        .onAppear { fieldIsFocused = true }
        .task(id: query) {
            if !query.isEmpty {
                try? await Task.sleep(for: Self.searchDelay)
                guard !Task.isCancelled else {
                    return
                }
            }
            await viewModel.search(query)
        }
    }

    /// Fits the sheet to its results instead of leaving a tall empty panel under a short list.
    private var resultsHeight: CGFloat {
        let rows = viewModel.results.reduce(CGFloat.zero) { height, result in
            height + (result.subtitle?.isEmpty == false ? Self.packageRowHeight : Self.pageRowHeight) + BrewSpacing.xxs
        }
        return min(rows + BrewSpacing.lg, Self.maximumResultsHeight)
    }

    private static let pageRowHeight: CGFloat = 36
    private static let packageRowHeight: CGFloat = 48
    private static let maximumResultsHeight: CGFloat = 360

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: BrewSpacing.xxs) {
                    ForEach(viewModel.results) { result in
                        GoToRow(result: result, isHighlighted: viewModel.highlightedResult == result)
                            .id(result.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.highlight(result)
                                activateHighlighted()
                            }
                    }
                }
                .padding(BrewSpacing.sm)
            }
            .onChange(of: viewModel.highlightedIndex) { _, _ in
                if let id = viewModel.highlightedResult?.id {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private func activateHighlighted() {
        guard let result = viewModel.highlightedResult else {
            return
        }
        onSelect(result.destination)
        dismiss()
    }
}

private struct GoToRow: View {
    let result: GoToResult
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: BrewSpacing.md) {
            Image(systemName: result.systemImage)
                .foregroundStyle(isHighlighted ? Color.brewTextBrand : Color.brewTextSecondary)
                .frame(width: BrewLayout.sidebarIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrewSpacing.xxs) {
                Text(verbatim: result.title)
                    .font(.brewBody)
                    .foregroundStyle(Color.brewTextPrimary)
                if let subtitle = result.subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.brewCaption)
                        .foregroundStyle(Color.brewTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(kindLabel)
                .font(.brewCaption)
                .foregroundStyle(Color.brewTextTertiary)
        }
        .padding(.horizontal, BrewSpacing.md)
        .padding(.vertical, BrewSpacing.sm)
        .background {
            RoundedRectangle(cornerRadius: BrewRadius.md)
                .fill(isHighlighted ? Color.brewBrandTint : Color.clear)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    private var kindLabel: String {
        switch result.kind {
        case .page:
            String(localized: "Page", bundle: #bundle, comment: "Go to palette: result is a sidebar page")
        case .installed:
            String(localized: "Installed", bundle: #bundle, comment: "Go to palette: result is an installed package")
        case .catalogue:
            String(localized: "Not installed", bundle: #bundle, comment: "Go to palette: result is a catalogue package to view in Discover")
        }
    }
}
