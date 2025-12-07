require 'rails_helper'

RSpec.describe 'WelcomeController', type: :routing do
  describe 'routing' do
    it 'routes to #home' do
      expect(get: "/welcome/home").to route_to("welcome#home")
    end
  end
end
