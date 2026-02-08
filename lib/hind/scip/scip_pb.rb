# frozen_string_literal: true

require 'google/protobuf'

Google::Protobuf::DescriptorPool.generated_pool.build do
  add_enum "scip.ProtocolVersion" do
    value :UnspecifiedProtocolVersion, 0
  end

  add_enum "scip.TextEncoding" do
    value :UnspecifiedTextEncoding, 0
    value :UTF8, 1
    value :UTF16, 2
  end

  add_message "scip.ToolInfo" do
    optional :name, :string, 1
    optional :version, :string, 2
    repeated :arguments, :string, 3
  end

  add_message "scip.Metadata" do
    optional :version, :enum, 1, "scip.ProtocolVersion"
    optional :tool_info, :message, 2, "scip.ToolInfo"
    optional :project_root, :string, 3
    optional :text_document_encoding, :enum, 4, "scip.TextEncoding"
  end

  add_enum "scip.PositionEncoding" do
    value :UnspecifiedPositionEncoding, 0
    value :UTF8CodeUnitOffsetFromLineStart, 1
    value :UTF16CodeUnitOffsetFromLineStart, 2
    value :UTF32CodeUnitOffsetFromLineStart, 3
  end

  add_enum "scip.SyntaxKind" do
    value :UnspecifiedSyntaxKind, 0
    value :Comment, 1
    value :Identifier, 41
    value :Keyword, 42
    value :StringLiteral, 49
  end

  add_enum "scip.Severity" do
    value :UnspecifiedSeverity, 0
    value :Error, 1
    value :Warning, 2
    value :Information, 3
    value :Hint, 4
  end

  add_enum "scip.DiagnosticTag" do
    value :UnspecifiedDiagnosticTag, 0
    value :Unnecessary, 1
    value :Deprecated, 2
  end

  add_message "scip.Diagnostic" do
    optional :severity, :enum, 1, "scip.Severity"
    optional :code, :string, 2
    optional :message, :string, 3
    optional :source, :string, 4
    repeated :tags, :enum, 5, "scip.DiagnosticTag"
  end

  add_message "scip.Relationship" do
    optional :symbol, :string, 1
    optional :is_reference, :bool, 2
    optional :is_implementation, :bool, 3
    optional :is_type_definition, :bool, 4
    optional :is_definition, :bool, 5
  end

  add_message "scip.Occurrence" do
    repeated :range, :int32, 1
    optional :symbol, :string, 2
    optional :symbol_roles, :int32, 3
    repeated :override_documentation, :string, 4
    optional :syntax_kind, :enum, 5, "scip.SyntaxKind"
    repeated :diagnostics, :message, 6, "scip.Diagnostic"
  end

  add_enum "scip.SymbolInformation.Kind" do
    value :UnspecifiedKind, 0
    value :Class, 7
    value :Method, 26
    value :Module, 29
    value :Package, 35
  end

  add_message "scip.Document" do
    optional :language, :string, 4
    optional :relative_path, :string, 1
    repeated :occurrences, :message, 2, "scip.Occurrence"
    repeated :symbols, :message, 3, "scip.SymbolInformation"
    optional :text, :string, 5
    optional :position_encoding, :enum, 6, "scip.PositionEncoding"
  end

  add_message "scip.SymbolInformation" do
    optional :symbol, :string, 1
    repeated :documentation, :string, 3
    repeated :relationships, :message, 4, "scip.Relationship"
    optional :kind, :enum, 5, "scip.SymbolInformation.Kind"
    optional :display_name, :string, 6
    optional :signature_documentation, :message, 7, "scip.Document"
    optional :snippet, :string, 8
  end

  add_message "scip.Index" do
    optional :metadata, :message, 1, "scip.Metadata"
    repeated :documents, :message, 2, "scip.Document"
    repeated :external_symbols, :message, 3, "scip.SymbolInformation"
  end
end

module Hind
  module SCIP
    Index = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.Index").msgclass
    Metadata = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.Metadata").msgclass
    ProtocolVersion = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.ProtocolVersion").enummodule
    TextEncoding = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.TextEncoding").enummodule
    ToolInfo = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.ToolInfo").msgclass
    Document = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.Document").msgclass
    PositionEncoding = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.PositionEncoding").enummodule
    Occurrence = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.Occurrence").msgclass
    SymbolInformation = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.SymbolInformation").msgclass
    SymbolInformation::Kind = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.SymbolInformation.Kind").enummodule
    Relationship = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.Relationship").msgclass
    SyntaxKind = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.SyntaxKind").enummodule
    Diagnostic = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.Diagnostic").msgclass
    Severity = Google::Protobuf::DescriptorPool.generated_pool.lookup("scip.Severity").enummodule
  end
end
