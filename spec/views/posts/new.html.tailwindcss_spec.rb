require "rails_helper"

RSpec.describe "posts/new" do
  before do
    assign(:post, Post.new(
                    title: "MyString",
                    body: "MyText"
                  ))
  end

  it "renders new post form" do
    render

    assert_select "form[action=?][method=?]", posts_path, "post" do
      assert_select "input[name=?]", "post[title]"

      assert_select "textarea[name=?]", "post[body]"

      assert_select "select[name=?]", "post[user_id]"
    end
  end
end
