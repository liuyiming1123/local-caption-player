import Foundation
@main struct CaptionTests {
 static func main() {
  let f = CaptionFormatter()
  assert(f.latest("你好，欢迎观看。今天讲能源。", maxUnits: 20) == "今天讲能源。")
  assert(f.latest("这是非常长的一句话需要合理地分成几个部分而且不能超出范围", maxUnits: 10).count <= 10)
  assert(f.latest("hello world testing", maxUnits: 13) == "testing")
  assert(f.latest("", maxUnits: 10) == "")
  print("caption tests passed")
 }
}
