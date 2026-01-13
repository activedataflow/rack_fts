# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rack::FTS::Stage do
  let(:test_stage_class) do
    Class.new(described_class) do
      protected
      
      def perform(context)
        Success(context.merge(test: "passed"))
      end
    end
  end
  
  let(:failing_stage_class) do
    Class.new(described_class) do
      protected
      
      def perform(context)
        Failure(error: "test error", stage: name)
      end
    end
  end
  
  let(:exception_stage_class) do
    Class.new(described_class) do
      protected
      
      def perform(context)
        raise StandardError, "test exception"
      end
    end
  end
  
  describe "#initialize" do
    it "sets the stage name" do
      stage = test_stage_class.new("test_stage")
      expect(stage.name).to eq("test_stage")
    end
    
    it "uses class name as default name" do
      stage = test_stage_class.new
      expect(stage.name).to be_a(String)
    end
  end
  
  describe "#call" do
    let(:context) { { data: "test" } }
    
    it "executes the stage and returns Success" do
      stage = test_stage_class.new("test")
      result = stage.call(context)
      
      expect(result).to be_success
      expect(result.value![:test]).to eq("passed")
    end
    
    it "returns Failure when stage fails" do
      stage = failing_stage_class.new("test")
      result = stage.call(context)
      
      expect(result).to be_failure
      expect(result.failure[:error]).to eq("test error")
    end
    
    it "catches exceptions and returns Failure" do
      stage = exception_stage_class.new("test")
      result = stage.call(context)
      
      expect(result).to be_failure
      expect(result.failure[:error]).to eq("test exception")
      expect(result.failure[:exception]).to eq("StandardError")
    end
  end
  
  describe "#performed?" do
    it "returns false before execution" do
      stage = test_stage_class.new("test")
      expect(stage.performed?).to be false
    end
    
    it "returns true after execution" do
      stage = test_stage_class.new("test")
      stage.call({})
      expect(stage.performed?).to be true
    end
  end
  
  describe "#success?" do
    it "returns true when stage succeeds" do
      stage = test_stage_class.new("test")
      stage.call({})
      expect(stage.success?).to be true
    end
    
    it "returns false when stage fails" do
      stage = failing_stage_class.new("test")
      stage.call({})
      expect(stage.success?).to be false
    end
  end
  
  describe "#failure?" do
    it "returns false when stage succeeds" do
      stage = test_stage_class.new("test")
      stage.call({})
      expect(stage.failure?).to be false
    end
    
    it "returns true when stage fails" do
      stage = failing_stage_class.new("test")
      stage.call({})
      expect(stage.failure?).to be true
    end
  end
  
  describe "#reset!" do
    it "resets the stage to unexecuted state" do
      stage = test_stage_class.new("test")
      stage.call({})
      expect(stage.performed?).to be true
      
      stage.reset!
      expect(stage.performed?).to be false
    end
  end
end
