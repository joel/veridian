require "rails_helper"

RSpec.describe "posts/index" do
  let!(:user) { create(:user) }

  before do
    assign(:posts, create_list(:post, 2, title: "Title",
                                         body: "MyText"))
  end

  it "renders a list of posts" do
    render

    cell_selector = "div#posts>div.post-card"
    assert_select cell_selector, text: Regexp.new("Title"), count: 2
    assert_select cell_selector, text: Regexp.new("MyText"), count: 2
    assert_select cell_selector, text: Regexp.new(nil.to_s), count: 2
  end
end
