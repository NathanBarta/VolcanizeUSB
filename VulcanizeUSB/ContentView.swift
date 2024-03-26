//
//  ContentView.swift
//  VulcanizeUSB
//
//  Created by Nathan Barta on 3/7/24.
//

import SwiftUI

struct ContentView: View {
  @StateObject var viewModel = HIDDeputy()
  
  var body: some View {
    VStack {
      Text("Hello, world!")
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
