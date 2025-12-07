require "rails_helper"

RSpec.describe "posts/show" do
  before do
    assign(:post, create(:post,
                         title: "Title",
                         body: "MyText"))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Title/)
    expect(rendered).to match(/MyText/)
    expect(rendered).to match(//)
  end
end
