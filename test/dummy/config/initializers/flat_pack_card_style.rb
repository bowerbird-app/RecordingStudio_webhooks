# frozen_string_literal: true

# Admin 4.2 still passes Card style:. Flatpack 0.1.319 raises on that keyword.
# outlined was a 2px border. default was the theme border.
module FlatPackCardStyleCompat
  def initialize(*args, style: nil, **kwargs, &block)
    case style&.to_sym
    when :outlined
      kwargs[:border] = :strong unless kwargs.key?(:border)
    when :default, nil
      nil
    else
      raise ArgumentError, "unknown keyword: :style"
    end

    super(*args, **kwargs, &block)
  end
end

Rails.application.config.to_prepare do
  component = FlatPack::Card::Component
  component.prepend(FlatPackCardStyleCompat) unless component < FlatPackCardStyleCompat
end
