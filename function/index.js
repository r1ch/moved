const AWS = require('aws-sdk')
const DB = new AWS.DynamoDB.DocumentClient()
const { v4: uuidv4 } = require('uuid');


const update = (from,to) => ({
  Key: {
      From: from
  },
  ExpressionAttributeNames: {
      "#to": "To",
      "#views": "Views",  
      "#from": "From"
  },
  ExpressionAttributeValues: {
    ":to": to,
    ":one" : 1
  },
  UpdateExpression: 'SET #to = if_not_exists(#to,:to), #views = #views + :one',
  ConditionExpression: 'attribute_exists(#from)',
  TableName: "LinkTable",
  ReturnValues: "ALL_NEW"
})

const next = from => ({
  Item: {
      From: from,
      Views: 0,
      Reached: Date.now()
  },
  ExpressionAttributeNames: {
    "#from":"From"
  },
  ConditionExpression: 'attribute_not_exists(#from)',
  TableName: "LinkTable"
})



const get = from => ({
  Key: {
      From: from
  },
  TableName: "LinkTable"
})

const claim = (resource,to) => DB.update(update(resource,to))
  .promise()
  .then(data=>{
    console.log("Conditional claim OK",data)
    //we know where to go, let's just make sure it exists
    let attr = data.Attributes
    return DB.put(next(attr.To))
    .promise()
    .then(()=>attr)
    .catch(error=>{
        console.log("Next already exists",error)
        return attr
    })
  })
  .catch(error=>{
    console.error("Conditional claim failed",error,resource,to)
    return DB.get(get(resource))
    .promise()
    .then(data=>data.Item)
  })


const someHTML = event => input => {
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'text/html',
    },
    body: `<!DOCTYPE html>
    <html>
    <head>
    <title>Page Title</title>
    </head>
    <body>
    
    ${input.Views==1 ?
      `<h1>You found me!</h1>
      <img src = "data:image/png;base64,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">
      `
      :
      `<h3>I've moved <a href = "${input.To}">here</a></h3>`
    }

    <h3>I was here ${new Date(input.Reached).toLocaleString()}</h3>
    <h4>So far ${input.Views} visitor${input.Views==1?" has made it here (you!)":"s have made it here (including you)"}</h4>

    </body>
    </html>`}
}


const someErrorHTML = event => input => ({
  statusCode: 200,
    headers: {
      'Content-Type': 'text/html',
    },
    body: `<!DOCTYPE html>
    <html>
    <head>
    <title>Page Title</title>
    </head>
    <body>
    
    <h1>The idea is to find the artwork</h1>
    <p>Start <a href = "/hello">here</a></p>
    <h4>Just beware - it moves</h4>
    </body>
    </html>`
})


module.exports.handler = async (event) => {
  const to = `/${uuidv4()}`
  return claim(event.path,to)
  .then(someHTML(event))
  .catch(someErrorHTML(event))
}
