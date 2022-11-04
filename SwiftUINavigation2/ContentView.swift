import SwiftUI

struct ContentView: View {
  var body: some View {
    DeferredView {
      NavigationStack {
        AView(
          model: AModel(//                    b: BModel(
            //                      c: CModel(
            //                        d: DModel(
            //                          e: EModel()
            //                        )
            //                      )
            //                    )
            )
        )
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}

@available(iOS 14, *)
final class AModel: ObservableObject {
  @Published var b: BModel?
  
  init(b: BModel? = nil) {
    self.b = b
  }
}

@available(iOS 14, *)
final class BModel: ObservableObject {
  @Published var c: CModel?

  init(c: CModel? = nil) {
    self.c = c
  }
}

@available(iOS 14, *)
final class CModel: ObservableObject {
  @Published var d: DModel?

  init(d: DModel? = nil) {
    self.d = d
  }
}

@available(iOS 14, *)
final class DModel: ObservableObject {
  @Published var e: EModel?

  init(e: EModel? = nil) {
    self.e = e
  }
}

@available(iOS 14, *)
final class EModel: ObservableObject {
  //  @Published var e: EModel?
  //
  //  init(e: EModel? = nil) {
  //    self.e = e
  //  }

}

@available(iOS 16, *)
struct AView: View {
  @ObservedObject var model: AModel
  @Environment(\.dismiss) var dismiss
  var body: some View {
    VStack {
      Button {
        self.model.b = .init()
      } label: {
        Text("Button to B")
      }

      Button {
        self.model.b = .init(c: .init(d: .init()))
      } label: {
        Text("Button to B-C-D")
      }
    }
    .navigationBarTitle(Text("A"))
    .navigationDestination(label: "A->B", unwrapping: self.$model.b) { $b in
      BView(model: b)
        .present(with: self.model, value: \.b)
        .environment(
          \.dismissByState,
          .init {
            self.model.b = nil
          })
    }
  }
}

@available(iOS 16, *)
struct BView: View {
  @ObservedObject var model: BModel
  @Environment(\.dismiss) var dismiss
  @Environment(\.dismissByState) var dismissByState
  var body: some View {
    VStack {
      Button("State dismissal") {
        self.dismissByState()
      }
      Button("Environment dismissal") {
        self.dismiss()
      }

      Button {
        self.model.c = .init()
      } label: {
        Text("Button to C")
      }

      Button {
        self.model.c = .init(d: .init(e: .init()))
      } label: {
        Text("Button to C-D-E")
      }
    }
    .navigationBarTitle(Text("B"))
    .navigationDestination(label: "B->C", unwrapping: self.$model.c) { $c in
      CView(model: c)
        .present(with: self.model, value: \.c)
        .environment(
          \.dismissByState,
          .init {
            self.model.c = nil
          })
    }
  }
}

@available(iOS 16, *)
struct CView: View {
  @ObservedObject var model: CModel
  @Environment(\.dismiss) var dismiss
  @Environment(\.dismissByState) var dismissByState
  @State var index: Int = 0
  var body: some View {
    VStack {
      Button("State dismissal") {
        self.dismissByState()
      }

      Button("Environment dismissal") {
        self.dismiss()
      }

      Button {
        self.model.d = .init()
      } label: {
        Text("Button to D")
      }

      Button {
        self.model.d = .init(e: .init())
      } label: {
        Text("Button to D-E")
      }
    }
    .navigationBarTitle(Text("C"))
    .navigationDestination(label: "C->D", unwrapping: self.$model.d) { $d in
      DView(model: d)
        .present(with: self.model, value: \.d)

        .environment(
          \.dismissByState,
          .init {
            self.model.d = nil
          })
    }
  }
}

@available(iOS 16, *)
struct DView: View {
  @ObservedObject var model: DModel
  @Environment(\.dismiss) var dismiss
  @Environment(\.dismissByState) var dismissByState

  var body: some View {
    VStack {
      Button("State dismissal") {
        self.dismissByState()
      }
      Button("Environment dismissal") {
        self.dismiss()
      }

      Button {
        self.model.e = .init()
      } label: {
        Text("Button to E")
      }

      //      Button {
      //        self.model.d = .init()
      //      } label: {
      //        Text("Button to E-")
      //      }
    }
    .navigationBarTitle(Text("D"))
    .navigationDestination(
      label: "D->E",
      unwrapping: self.$model.e) { $e in
      EView(model: e)
        .present(with: self.model, value: \.e)

        .environment(
          \.dismissByState,
          .init {
            self.model.e = nil
          })
    }
  }
}

@available(iOS 16, *)
struct EView: View {
  @ObservedObject var model: EModel
  @Environment(\.dismiss) var dismiss
  @Environment(\.dismissByState) var dismissByState

  var body: some View {
    VStack {
      Button("State dismissal") {
        self.dismissByState()
      }
      Button("Environment dismissal") {
        self.dismiss()
      }

      //      Button {
      //        self.model.e = .init()
      //      } label: {
      //        Text("Button to F")
      //      }
      //
      //      Button {
      //        self.model.d = .init()
      //      } label: {
      //        Text("Button to F-")
      //      }
    }
    .navigationBarTitle(Text("E"))
    //    .navigationDestination(unwrapping: self.$model.e) { $e in
    //      VStack {
    //        Button("State dismissal") {
    //          self.model.e = nil
    //        }
    //        EView(model: e)
    //      }
    //    }
  }
}
