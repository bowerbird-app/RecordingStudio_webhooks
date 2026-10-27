# frozen_string_literal: true

# Sibling tags still declare recording_studio ~> 4.x. Bundler reads those
# gemspecs during install and again in Bundler.setup. Rewrite that one
# requirement in place so 6.1.0 can activate. Require this file before
# Bundler.setup. Return the original array: Gem::Specification#add_dependency
# appends to whatever #dependencies returns.
module WidenRecordingStudioRequirement
  TARGET = Gem::Version.new("6.1.0")
  REQUIREMENT = Gem::Requirement.new(">= #{TARGET}")

  module SpecificationDependencies
    def dependencies
      deps = super
      deps.each { |dependency| WidenRecordingStudioRequirement.relax!(dependency) }
      deps
    end
  end

  def self.relax!(dependency)
    return unless dependency.name == "recording_studio"
    return if dependency.requirement.satisfied_by?(TARGET)

    dependency.instance_variable_set(:@requirement, REQUIREMENT)
    dependency.instance_variable_set(:@version_requirements, REQUIREMENT)
  end

  def self.install!
    return if Gem::Specification < SpecificationDependencies

    Gem::Specification.prepend(SpecificationDependencies)
  end
end

WidenRecordingStudioRequirement.install!
