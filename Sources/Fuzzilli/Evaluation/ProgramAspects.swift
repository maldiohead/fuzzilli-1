// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Aspects of a program that make it special.
public class ProgramAspects: CustomStringConvertible {
    let outcome: ExecutionOutcome
    
    init(outcome: ExecutionOutcome) {
        self.outcome = outcome
    }

    public var description: String {
        return "execution outcome \(outcome)"
    }

    public static func == (lhs: ProgramAspects, rhs: ProgramAspects) -> Bool {
        return lhs.outcome == rhs.outcome
    }

    //TODO: This isn't the best design, as this only really makes sense in CovEdgeSet
    public func toEdges() -> [UInt64] {
        return []
    }

}
