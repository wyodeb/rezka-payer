//
//  SearchBarView.swift
//  rezka-player
//
//  Created by vitalii on 10.11.2022.
//  Copyright © 2022 IGR Soft. All rights reserved.
//

import SwiftUI

struct SearchBarView<Content: View>: UIViewControllerRepresentable {
    
    typealias UIViewControllerType = UINavigationController
    
    @Binding var text: String
    
    var placeholder: String = ""
    var onTextChange: ((String) -> Void)? = nil
    @ViewBuilder var content: () -> Content

    class Coordinator: NSObject, UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate {

        @Binding var text: String
        var onTextChange: ((String) -> Void)?

        init(text: Binding<String>, onTextChange: ((String) -> Void)?) {
            _text = text
            self.onTextChange = onTextChange
        }
        
        func updateSearchResults(for searchController: UISearchController) {
            let newText = searchController.searchBar.text ?? ""
            if self.text != newText {
                self.text = newText
                onTextChange?(newText)
            }
        }
        
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        }
        
        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        }
    }

    func makeCoordinator() -> SearchBarView.Coordinator {
        return Coordinator(text: $text, onTextChange: onTextChange)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<SearchBarView>) -> UIViewControllerType {
        let topController = UIHostingController(rootView: content() )
        
        let searchController =  UISearchController(searchResultsController: topController)
        searchController.searchResultsUpdater = context.coordinator
        searchController.searchBar.placeholder = placeholder
        
        let searchContainer = UISearchContainerViewController(searchController: searchController)
        let searchNavigationController = UINavigationController(rootViewController: searchContainer)

        return searchNavigationController
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: UIViewControllerRepresentableContext<SearchBarView>) {
        // Intentionally not reassigning host.rootView here:
        // the hosted SwiftUI view observes its environment / view-model and
        // updates itself. Reassigning on every parent update causes the grid
        // to fully re-render and the tvOS focus engine to lose its place.
    }
}

struct SearchBarView_Previews: PreviewProvider {
    static var previews: some View {
        SearchBarView(text: .constant("")) {
        }
    }
}
