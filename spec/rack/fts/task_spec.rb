# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rack::FTS::Task do
  let(:success_stage) do
    Class.new(Rack::FTS::Stage) do
      protected
      def perform(context)
        Success(context.merge(stage_name => "passed"))
      end
      
      def stage_name
        name
      end
    end
  end
  
  let(:failure_stage) do
    Class.new(Rack::FTS::Stage) do
      protected
      def perform(context)
        Failure(error: "stage failed", stage: name)
      end
    end
  end
  
  describe "#add_stage" do
    it "adds a stage to the task" do
      task = described_class.new
      stage = success_stage.new("test")
      
      task.add_stage(stage)
      expect(task.stages).to include(stage)
    end
    
    it "returns self for chaining" do
      task = described_class.new
      stage = success_stage.new("test")
      
      result = task.add_stage(stage)
      expect(result).to eq(task)
    end
    
    it "raises error if stage is not a Stage" do
      task = described_class.new
      
      expect { task.add_stage("not a stage") }.to raise_error(ArgumentError)
    end
  end
  
  describe "#run" do
    let(:env) { Rack::MockRequest.env_for("/test") }
    
    it "runs all stages successfully" do
      task = described_class.new
      task.add_stage(success_stage.new("stage1"))
      task.add_stage(success_stage.new("stage2"))
      
      result = task.run(env)
      
      expect(result).to be_success
      expect(result.value![:stage1]).to eq("passed")
      expect(result.value![:stage2]).to eq("passed")
    end
    
    it "short-circuits on first failure" do
      task = described_class.new
      task.add_stage(success_stage.new("stage1"))
      task.add_stage(failure_stage.new("stage2"))
      task.add_stage(success_stage.new("stage3"))
      
      result = task.run(env)
      
      expect(result).to be_failure
      expect(result.failure[:error]).to eq("stage failed")
      expect(task.stages[0].success?).to be true
      expect(task.stages[1].failure?).to be true
      expect(task.stages[2].performed?).to be false
    end
  end
  
  describe "#all_successful?" do
    let(:env) { Rack::MockRequest.env_for("/test") }
    
    it "returns true when all stages succeed" do
      task = described_class.new
      task.add_stage(success_stage.new("stage1"))
      task.add_stage(success_stage.new("stage2"))
      
      task.run(env)
      expect(task.all_successful?).to be true
    end
    
    it "returns false when any stage fails" do
      task = described_class.new
      task.add_stage(success_stage.new("stage1"))
      task.add_stage(failure_stage.new("stage2"))
      
      task.run(env)
      expect(task.all_successful?).to be false
    end
  end
  
  describe "#any_failed?" do
    let(:env) { Rack::MockRequest.env_for("/test") }
    
    it "returns false when all stages succeed" do
      task = described_class.new
      task.add_stage(success_stage.new("stage1"))
      task.add_stage(success_stage.new("stage2"))
      
      task.run(env)
      expect(task.any_failed?).to be false
    end
    
    it "returns true when any stage fails" do
      task = described_class.new
      task.add_stage(success_stage.new("stage1"))
      task.add_stage(failure_stage.new("stage2"))
      
      task.run(env)
      expect(task.any_failed?).to be true
    end
  end
  
  describe "#reset!" do
    let(:env) { Rack::MockRequest.env_for("/test") }
    
    it "resets all stages" do
      task = described_class.new
      task.add_stage(success_stage.new("stage1"))
      task.add_stage(success_stage.new("stage2"))
      
      task.run(env)
      expect(task.stages.all?(&:performed?)).to be true
      
      task.reset!
      expect(task.stages.all?(&:performed?)).to be false
    end
  end
end
